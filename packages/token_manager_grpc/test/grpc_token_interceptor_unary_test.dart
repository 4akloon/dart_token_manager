import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/bearer_delegate.dart';
import 'helpers/fake_unary_invoker.dart';
import 'helpers/grpc_fixture.dart';

final class _PermissionDeniedDelegate extends BearerDelegate {
  const _PermissionDeniedDelegate();

  @override
  bool shouldRefresh(grpc.GrpcError? error) =>
      error?.code == grpc.StatusCode.permissionDenied;
}

void main() {
  const unauthenticated = grpc.GrpcError.unauthenticated();
  late GrpcFixture fixture;
  late FakeUnaryInvoker<String, String> invoker;

  setUp(() {
    fixture = GrpcFixture();
    invoker = FakeUnaryInvoker<String, String>();
  });

  grpc.ResponseFuture<String> call({grpc.CallOptions? options}) =>
      fixture.interceptor.interceptUnary<String, String>(
        GrpcFixture.method,
        'ping',
        options ?? grpc.CallOptions(),
        invoker.invoke,
      );

  test(
    'sends the call with the token metadata and the caller options',
    () async {
      final response = call(options: grpc.CallOptions(metadata: {'x': '1'}));
      await GrpcFixture.settle();
      invoker.calls.single.succeed('pong');

      expect(await response, 'pong');
      expect(invoker.calls.single.options.metadata, {
        'x': '1',
        'authorization': 'Bearer t0',
      });
    },
  );

  test('fails with NotAuthenticated without calling when signed out', () async {
    fixture = GrpcFixture(signedIn: false);

    await expectLater(call(), throwsA(isA<NotAuthenticated>()));
    expect(invoker.calls, isEmpty);
  });

  test('replays once with refreshed tokens after UNAUTHENTICATED', () async {
    final response = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].succeed('pong');

    expect(await response, 'pong');
    expect(invoker.calls.map((call) => call.authorization), [
      'Bearer t0',
      'Bearer t1',
    ]);
    expect(fixture.refresher.calls, 1);
  });

  test('a second UNAUTHENTICATED is surfaced after one replay', () async {
    final response = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].fail(unauthenticated);

    await expectLater(response, throwsA(unauthenticated));
    expect(invoker.calls, hasLength(2));
    expect(fixture.refresher.calls, 1);
  });

  test('another gRPC error is surfaced without a replay', () async {
    const unavailable = grpc.GrpcError.unavailable();
    final response = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(unavailable);

    await expectLater(response, throwsA(unavailable));
    expect(invoker.calls, hasLength(1));
    expect(fixture.refresher.calls, 0);
  });

  test('the delegate decides which errors are auth failures', () async {
    fixture = GrpcFixture(delegate: const _PermissionDeniedDelegate());
    final response = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(const grpc.GrpcError.permissionDenied());
    await GrpcFixture.settle();
    invoker.calls[1].succeed('pong');

    expect(await response, 'pong');
    expect(fixture.refresher.calls, 1);
  });

  test('headers and trailers come from the replayed call', () async {
    invoker.metadataByCall.addAll({
      0: {'call': '0'},
      1: {'call': '1'},
    });
    final response = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].succeed('pong');
    await response;

    expect(await response.headers, {'call': '1'});
    expect(await response.trailers, {'call': '1'});
  });

  test('headers are empty when no call was made', () async {
    fixture = GrpcFixture(signedIn: false);
    final response = call();
    await expectLater(response, throwsA(isA<NotAuthenticated>()));

    expect(await response.headers, isEmpty);
  });

  test('cancel reaches the call in flight', () async {
    final response = call();
    await GrpcFixture.settle();

    await response.cancel();

    expect(invoker.calls.single.cancelled, isTrue);
    await expectLater(response, throwsA(isA<grpc.GrpcError>()));
  });

  test('cancel during the refresh prevents the replay', () async {
    fixture.refresher.gate = Completer<void>();
    final response = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(unauthenticated);
    await GrpcFixture.settle();

    await response.cancel();
    fixture.refresher.gate?.complete();

    await expectLater(
      response,
      throwsA(
        isA<grpc.GrpcError>().having(
          (error) => error.code,
          'code',
          grpc.StatusCode.cancelled,
        ),
      ),
    );
    expect(invoker.calls, hasLength(1));
  });

  test('concurrent rejected calls share one refresh', () async {
    final first = call();
    final second = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(unauthenticated);
    invoker.calls[1].fail(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[2].succeed('a');
    invoker.calls[3].succeed('b');

    expect(await Future.wait([first, second]), ['a', 'b']);
    expect(fixture.refresher.calls, 1);
  });

  test('a failing header future does not escape to the zone', () async {
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      invoker.metadataFailure = Exception('lost');
      final response = call();
      await GrpcFixture.settle();
      invoker.calls.single.succeed('pong');
      await response;
      await GrpcFixture.settle();
    }, (error, stackTrace) => uncaught.add(error));

    expect(uncaught, isEmpty);
  });
}
