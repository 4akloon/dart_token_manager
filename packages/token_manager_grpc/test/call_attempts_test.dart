import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';
import 'package:token_manager_grpc/src/call_attempts.dart';

import 'helpers/fake_unary_call.dart';

void main() {
  FakeUnaryCall<String> fakeCall(
    Map<String, String> metadata, {
    Exception? metadataFailure,
  }) => FakeUnaryCall<String>(
    grpc.CallOptions(),
    metadata: metadata,
    metadataFailure: metadataFailure,
  );

  test('headers and trailers are empty when no call was made', () async {
    final attempts = CallAttempts()..settle();

    expect(await attempts.headers, isEmpty);
    expect(await attempts.trailers, isEmpty);
  });

  test('headers stay pending until the attempts settle', () async {
    final attempts = CallAttempts();
    attempts.unary(() => fakeCall({'call': '1'}));
    var resolved = false;
    unawaited(attempts.headers.then((_) => resolved = true));
    await Future<void>.delayed(Duration.zero);

    expect(resolved, isFalse);
    attempts.settle();
    expect(await attempts.headers, {'call': '1'});
  });

  test('headers and trailers follow the latest call', () async {
    final attempts = CallAttempts();
    attempts
      ..unary(() => fakeCall({'call': '1'}))
      ..unary(() => fakeCall({'call': '2'}))
      ..settle();

    expect(await attempts.headers, {'call': '2'});
    expect(await attempts.trailers, {'call': '2'});
  });

  test('settleWhenDone settles after the response fails', () async {
    final attempts = CallAttempts();
    final call = attempts.unary(() => fakeCall({'call': '1'}));
    attempts.settleWhenDone(call);

    (call as FakeUnaryCall<String>).fail(Exception('boom'));

    expect(await attempts.headers, {'call': '1'});
  });

  test('cancel cancels the latest call', () async {
    final attempts = CallAttempts();
    final call = fakeCall({});
    attempts.unary(() => call);
    unawaited(call.then((_) {}, onError: (_) {}));

    await attempts.cancel();

    expect(call.cancelled, isTrue);
  });

  test('a call after cancel fails as cancelled without being made', () async {
    final attempts = CallAttempts();
    await attempts.cancel();
    var made = false;

    expect(
      () => attempts.unary(() {
        made = true;
        return fakeCall({});
      }),
      throwsA(
        isA<grpc.GrpcError>().having(
          (error) => error.code,
          'code',
          grpc.StatusCode.cancelled,
        ),
      ),
    );
    expect(made, isFalse);
  });

  test('a failing header future reaches the caller, not the zone', () async {
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      CallAttempts()
        ..unary(() => fakeCall({}, metadataFailure: Exception('lost')))
        ..settle();
      await Future<void>.delayed(Duration.zero);
    }, (error, stackTrace) => uncaught.add(error));

    expect(uncaught, isEmpty);
  });

  test('an awaited failing header future throws its error', () async {
    final attempts = CallAttempts()
      ..unary(() => fakeCall({}, metadataFailure: Exception('lost')))
      ..settle();

    await expectLater(attempts.headers, throwsA(isA<Exception>()));
  });
}
