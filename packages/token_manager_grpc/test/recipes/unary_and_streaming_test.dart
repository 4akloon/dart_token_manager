import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/unary_and_streaming.dart'
    show GrpcSession, StandInExchange, TokenExchange;
import '../helpers/fake_stream_invoker.dart';
import '../helpers/fake_unary_invoker.dart';
import '../helpers/grpc_fixture.dart';

/// An exchange the auth service answers with [error].
final class _FailingExchange implements TokenExchange {
  const _FailingExchange(this.error);

  final grpc.GrpcError error;

  @override
  Future<TokenSet> exchange(String refreshToken) async => throw error;
}

/// An exchange that wrongly goes through the interceptor of the session.
final class _InterceptedExchange implements TokenExchange {
  _InterceptedExchange(this.invoker);

  final FakeUnaryInvoker<String, String> invoker;

  /// Set once the session exists; the session needs this exchange first.
  GrpcSession? session;

  @override
  Future<TokenSet> exchange(String refreshToken) async {
    await session?.interceptor.interceptUnary<String, String>(
      GrpcFixture.method,
      'exchange',
      grpc.CallOptions(),
      invoker.invoke,
    );
    return const TokenSet(accessToken: 'access-1');
  }
}

/// A signed-in [GrpcSession] and the calls the tests make through it.
final class _Calls {
  _Calls._(this.session);

  static Future<_Calls> signedIn(TokenExchange exchange) async {
    final session = GrpcSession(
      channel: grpc.ClientChannel('localhost', port: 1),
      exchange: exchange,
    );
    await session.manager.setTokens(
      const TokenSet(accessToken: 'access-0', refreshToken: 'refresh'),
    );
    addTearDown(session.close);
    return _Calls._(session);
  }

  final GrpcSession session;

  grpc.ResponseFuture<String> unary(FakeUnaryInvoker<String, String> invoker) =>
      session.interceptor.interceptUnary<String, String>(
        GrpcFixture.method,
        'ping',
        grpc.CallOptions(),
        invoker.invoke,
      );

  Stream<String> streaming(
    FakeStreamInvoker<String, String> invoker,
    Stream<String> requests,
  ) => session.interceptor.interceptStreaming<String, String>(
    GrpcFixture.method,
    requests,
    grpc.CallOptions(),
    invoker.invoke,
  );
}

void main() {
  const unauthenticated = grpc.GrpcError.unauthenticated();
  // Assigned in setUp, which runs before every test.
  late StandInExchange exchange;
  late _Calls calls;

  setUp(() async {
    exchange = StandInExchange();
    calls = await _Calls.signedIn(exchange);
  });

  test('two unary calls rejected together share one refresh', () async {
    final invoker = FakeUnaryInvoker<String, String>();
    final first = calls.unary(invoker);
    final second = calls.unary(invoker);
    await GrpcFixture.settle();

    invoker.calls[0].fail(unauthenticated);
    invoker.calls[1].fail(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[2].succeed('pong');
    invoker.calls[3].succeed('pong');

    expect(await Future.wait([first, second]), ['pong', 'pong']);
    expect(exchange.calls, 1);
    expect(invoker.calls.map((call) => call.authorization), [
      'Bearer access-0',
      'Bearer access-0',
      'Bearer access-1',
      'Bearer access-1',
    ]);
  });

  test('a unary call is replayed only once', () async {
    final invoker = FakeUnaryInvoker<String, String>();
    final failure = expectLater(
      calls.unary(invoker),
      throwsA(isA<grpc.GrpcError>()),
    );
    await GrpcFixture.settle();

    invoker.calls[0].fail(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].fail(unauthenticated);

    await failure;
    expect(invoker.calls, hasLength(2));
  });

  test('a streaming call is reopened once before its first response', () async {
    final invoker = FakeStreamInvoker<String, String>();
    addTearDown(invoker.closeAll);
    final received = <String>[];
    final subscription = calls
        .streaming(invoker, Stream<String>.value('ping'))
        .listen(received.add);
    await GrpcFixture.settle();

    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].responses.add('a');
    await GrpcFixture.settle();

    expect(invoker.calls.map((call) => call.authorization), [
      'Bearer access-0',
      'Bearer access-1',
    ]);
    expect(received, ['a']);
    expect(invoker.calls[1].sent, ['ping']);
    await subscription.cancel();
  });

  test('a streaming call that got a response is not reopened', () async {
    final invoker = FakeStreamInvoker<String, String>();
    addTearDown(invoker.closeAll);
    final received = <String>[];
    final errors = <Object>[];
    final subscription = calls
        .streaming(invoker, Stream<String>.value('ping'))
        .listen(received.add, onError: errors.add);
    await GrpcFixture.settle();

    invoker.calls[0].responses.add('a');
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();

    expect(received, ['a']);
    expect(errors, [unauthenticated]);
    expect(invoker.calls, hasLength(1));
    expect(exchange.calls, 0);
    await subscription.cancel();
  });

  test(
    'a streaming call whose request stream is open is not reopened',
    () async {
      final invoker = FakeStreamInvoker<String, String>();
      addTearDown(invoker.closeAll);
      final requests = StreamController<String>()..add('one');
      addTearDown(requests.close);
      final errors = <Object>[];
      final subscription = calls
          .streaming(invoker, requests.stream)
          .listen((_) {}, onError: errors.add);
      await GrpcFixture.settle();

      invoker.calls[0].responses.addError(unauthenticated);
      await GrpcFixture.settle();

      expect(errors, [unauthenticated]);
      expect(invoker.calls, hasLength(1));
      await subscription.cancel();
    },
  );

  test('a streaming call that sent two requests is not reopened', () async {
    final invoker = FakeStreamInvoker<String, String>();
    addTearDown(invoker.closeAll);
    final errors = <Object>[];
    final subscription = calls
        .streaming(invoker, Stream<String>.fromIterable(['one', 'two']))
        .listen((_) {}, onError: errors.add);
    await GrpcFixture.settle();

    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();

    expect(errors, [unauthenticated]);
    expect(invoker.calls, hasLength(1));
    await subscription.cancel();
  });

  test('a call that is not reopened reports its rejected tokens', () async {
    final invoker = FakeStreamInvoker<String, String>();
    addTearDown(invoker.closeAll);
    final subscription = calls
        .streaming(invoker, Stream<String>.fromIterable(['one', 'two']))
        .listen((_) {}, onError: (Object _) {});
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();

    final next = FakeUnaryInvoker<String, String>();
    final response = calls.unary(next);
    await GrpcFixture.settle();
    next.calls[0].succeed('pong');

    expect(await response, 'pong');
    expect(exchange.calls, 1);
    expect(next.calls.single.authorization, 'Bearer access-1');
    await subscription.cancel();
  });

  test('a rejected refresh token fails the call with InvalidGrant', () async {
    calls = await _Calls.signedIn(
      const _FailingExchange(unauthenticated),
    );
    final invoker = FakeUnaryInvoker<String, String>();
    final failure = expectLater(
      calls.unary(invoker),
      throwsA(isA<InvalidGrant>()),
    );
    await GrpcFixture.settle();

    invoker.calls[0].fail(unauthenticated);

    await failure;
    expect(await calls.session.manager.current(), isNull);
  });

  test(
    'an UNAVAILABLE exchange fails the call and keeps the session',
    () async {
      calls = await _Calls.signedIn(
        const _FailingExchange(grpc.GrpcError.unavailable()),
      );
      final invoker = FakeUnaryInvoker<String, String>();
      final failure = expectLater(
        calls.unary(invoker),
        throwsA(isA<Transient>()),
      );
      await GrpcFixture.settle();

      invoker.calls[0].fail(unauthenticated);

      await failure;
      final kept = await calls.session.manager.current();
      expect(kept?.accessToken, 'access-0');
      expect(kept?.refreshToken, 'refresh');
    },
  );

  test(
    'a PERMISSION_DENIED answer reaches the caller without a refresh',
    () async {
      const denied = grpc.GrpcError.permissionDenied();
      final invoker = FakeUnaryInvoker<String, String>();
      final failure = expectLater(calls.unary(invoker), throwsA(denied));
      await GrpcFixture.settle();

      invoker.calls[0].fail(denied);

      await failure;
      expect(exchange.calls, 0);
      expect(invoker.calls, hasLength(1));
    },
  );

  test(
    'a rejected exchange call waits for the refresh it belongs to',
    () async {
      final invoker = FakeUnaryInvoker<String, String>();
      final intercepted = _InterceptedExchange(invoker);
      calls = await _Calls.signedIn(intercepted);
      intercepted.session = calls.session;
      final response = calls.unary(invoker);
      var completed = false;
      unawaited(
        response
            .then((_) {}, onError: (Object _) {})
            .then(
              (_) => completed = true,
            ),
      );
      await GrpcFixture.settle();
      invoker.calls[0].fail(unauthenticated);
      await GrpcFixture.settle();
      invoker.calls[1].fail(unauthenticated);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(invoker.calls, hasLength(2));
      expect(completed, isFalse);
      expect(
        invoker.calls.where((call) => call.authorization == 'Bearer access-1'),
        isEmpty,
      );
    },
  );
}
