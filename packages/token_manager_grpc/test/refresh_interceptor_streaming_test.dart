import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/fake_stream_invoker.dart';
import 'helpers/grpc_fixture.dart';

void main() {
  const unauthenticated = grpc.GrpcError.unauthenticated();
  late GrpcFixture fixture;
  late FakeStreamInvoker<String, String> invoker;
  late List<String> received;
  late List<Object> errors;

  setUp(() {
    fixture = GrpcFixture();
    invoker = FakeStreamInvoker<String, String>();
    received = [];
    errors = [];
  });

  tearDown(() => invoker.closeAll());

  grpc.ResponseStream<String> open([Stream<String>? requests]) =>
      fixture.interceptor.interceptStreaming<String, String>(
        GrpcFixture.method,
        requests ?? Stream<String>.fromIterable(['ping']),
        grpc.CallOptions(),
        invoker.invoke,
      );

  StreamSubscription<String> listen(grpc.ResponseStream<String> stream) =>
      stream.listen(received.add, onError: errors.add);

  test('opens the call with the token metadata and relays responses', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();
    invoker.calls.single.responses
      ..add('a')
      ..add('b');
    await GrpcFixture.settle();

    expect(invoker.calls.single.authorization, 'Bearer t0');
    expect(received, ['a', 'b']);
    await subscription.cancel();
  });

  test('fails with NotAuthenticated without calling when signed out', () async {
    fixture = GrpcFixture(signedIn: false);
    final subscription = listen(open());
    await GrpcFixture.settle();

    expect(errors.single, isA<NotAuthenticated>());
    expect(invoker.calls, isEmpty);
    await subscription.cancel();
  });

  test('UNAUTHENTICATED before the first response reopens once with the '
      'same request', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].responses.add('a');
    await GrpcFixture.settle();

    expect(invoker.calls.map((call) => call.authorization), [
      'Bearer t0',
      'Bearer t1',
    ]);
    expect(invoker.calls[1].sent, ['ping']);
    expect(invoker.calls[0].cancelled, isTrue);
    expect(received, ['a']);
    expect(errors, isEmpty);
    await subscription.cancel();
  });

  test('UNAUTHENTICATED after the first response is surfaced, not '
      'replayed', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();
    invoker.calls.single.responses
      ..add('a')
      ..addError(unauthenticated);
    await GrpcFixture.settle();

    expect(received, ['a']);
    expect(errors, [unauthenticated]);
    expect(invoker.calls, hasLength(1));
    expect(fixture.refresher.calls, 0);
    await subscription.cancel();
  });

  test('a second UNAUTHENTICATED is surfaced after one reopen', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].responses.addError(unauthenticated);
    await GrpcFixture.settle();

    expect(errors, [unauthenticated]);
    expect(invoker.calls, hasLength(2));
    expect(fixture.refresher.calls, 1);
    await subscription.cancel();
  });

  test('a client stream with several requests is never reopened', () async {
    final subscription = listen(
      open(Stream<String>.fromIterable(['one', 'two'])),
    );
    await GrpcFixture.settle();
    invoker.calls.single.responses.addError(unauthenticated);
    await GrpcFixture.settle();

    expect(errors, [unauthenticated]);
    expect(invoker.calls, hasLength(1));
    await subscription.cancel();
  });

  test('a rejected client stream asks for a refresh with the rejected token '
      'and still surfaces the error', () async {
    final subscription = listen(
      open(Stream<String>.fromIterable(['one', 'two'])),
    );
    await GrpcFixture.settle();
    invoker.calls.single.responses.addError(unauthenticated);
    await GrpcFixture.settle();

    expect(fixture.refresher.calls, 1);
    expect(fixture.refresher.replaced, ['t0']);
    expect(errors, [unauthenticated]);
    expect(invoker.calls, hasLength(1));
    await subscription.cancel();
  });

  test('a replayable stream does not report its rejection a second '
      'time', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].responses.add('a');
    await GrpcFixture.settle();

    expect(fixture.refresher.calls, 1);
    expect(invoker.calls, hasLength(2));
    await subscription.cancel();
  });

  test('pause and resume reach the call', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();

    subscription.pause();
    expect(invoker.calls.single.responses.isPaused, isTrue);
    subscription.resume();
    expect(invoker.calls.single.responses.isPaused, isFalse);
    await subscription.cancel();
  });

  test('cancelling the subscription cancels the call', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();

    await subscription.cancel();

    expect(invoker.calls.single.cancelled, isTrue);
  });

  test('cancel on the response stream cancels the current call', () async {
    final stream = open();
    final subscription = listen(stream);
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();

    await stream.cancel();
    await GrpcFixture.settle();

    expect(invoker.calls[1].cancelled, isTrue);
    expect(errors.single, isA<grpc.GrpcError>());
    await subscription.cancel();
  });

  test('headers and trailers come from the reopened call', () async {
    invoker.metadataByCall.addAll({
      0: {'call': '0'},
      1: {'call': '1'},
    });
    final stream = open();
    final subscription = listen(stream);
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].responses.add('a');

    expect(await stream.headers, {'call': '1'});
    expect(await stream.trailers, {'call': '1'});
    await subscription.cancel();
  });

  test('single answers with the only response and its headers', () async {
    invoker.metadataByCall[0] = {'call': '0'};
    final response = open().single;
    await GrpcFixture.settle();
    invoker.calls.single.responses.add('a');
    await invoker.calls.single.responses.close();

    expect(await response, 'a');
    expect(await response.headers, {'call': '0'});
  });

  test('concurrent rejected streams share one refresh', () async {
    final first = listen(open());
    final second = listen(open());
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    invoker.calls[1].responses.addError(unauthenticated);
    await GrpcFixture.settle();

    expect(invoker.calls, hasLength(4));
    expect(fixture.refresher.calls, 1);
    await first.cancel();
    await second.cancel();
  });

  test('cancelling before the token arrives never makes a call', () async {
    final stream = open();
    final subscription = listen(stream);

    await subscription.cancel();
    await GrpcFixture.settle();

    expect(invoker.calls, isEmpty);
    expect(await stream.headers, isEmpty);
  });

  test('cancel during the refresh never opens a second call', () async {
    fixture.refresher.gate = Completer<void>();
    final stream = open();
    final subscription = listen(stream);
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();

    await stream.cancel();
    fixture.refresher.gate?.complete();
    await GrpcFixture.settle();

    expect(invoker.calls, hasLength(1));
    expect(
      errors.single,
      isA<grpc.GrpcError>().having(
        (error) => error.code,
        'code',
        grpc.StatusCode.cancelled,
      ),
    );
    await subscription.cancel();
  });
}
