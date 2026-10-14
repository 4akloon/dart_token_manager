import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';
import 'package:token_manager_grpc/src/call_attempts.dart';
import 'package:token_manager_grpc/src/settling_stream.dart';

import 'helpers/fake_unary_call.dart';

void main() {
  late StreamController<int> source;
  late CallAttempts attempts;
  late bool settled;

  setUp(() {
    source = StreamController<int>();
    attempts = CallAttempts()
      ..unary(
        () => FakeUnaryCall<int>(grpc.CallOptions(), metadata: {'call': '1'}),
      );
    settled = false;
    unawaited(attempts.headers.then((_) => settled = true));
  });

  tearDown(() => source.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('relays events and settles on the first one', () async {
    final received = <int>[];
    final subscription = SettlingStream<int>(
      source.stream,
      attempts,
    ).stream.listen(received.add);
    await settle();
    expect(settled, isFalse);

    source.add(1);
    await settle();

    expect(received, [1]);
    expect(settled, isTrue);
    await subscription.cancel();
  });

  test('settles on the first error', () async {
    final subscription = SettlingStream<int>(
      source.stream,
      attempts,
    ).stream.listen((_) {}, onError: (_) {});

    source.addError(Exception('boom'));
    await settle();

    expect(settled, isTrue);
    await subscription.cancel();
  });

  test('settles and ends when the source ends', () async {
    var done = false;
    final subscription = SettlingStream<int>(
      source.stream,
      attempts,
    ).stream.listen((_) {}, onDone: () => done = true);

    await source.close();
    await settle();

    expect(settled, isTrue);
    expect(done, isTrue);
    await subscription.cancel();
  });

  test('settles when cancelled before any event', () async {
    final subscription = SettlingStream<int>(
      source.stream,
      attempts,
    ).stream.listen((_) {});
    await settle();

    await subscription.cancel();
    await settle();

    expect(settled, isTrue);
  });

  test('pause, resume and cancel reach the source', () async {
    var cancelled = false;
    source.onCancel = () => cancelled = true;
    final subscription = SettlingStream<int>(
      source.stream,
      attempts,
    ).stream.listen((_) {});

    subscription.pause();
    expect(source.isPaused, isTrue);
    subscription.resume();
    expect(source.isPaused, isFalse);
    await subscription.cancel();
    expect(cancelled, isTrue);
  });
}
