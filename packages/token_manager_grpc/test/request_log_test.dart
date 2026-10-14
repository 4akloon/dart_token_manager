import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager_grpc/src/request_log.dart';

void main() {
  test('the first call reads the original requests', () async {
    final log = RequestLog<int>(Stream<int>.fromIterable([1]));

    expect(await log.next().toList(), [1]);
  });

  test('a single ended request is replayable and sent again', () async {
    final log = RequestLog<int>(Stream<int>.fromIterable([1]));
    await log.next().toList();

    expect(log.isReplayable, isTrue);
    expect(await log.next().toList(), [1]);
  });

  test('requests that have not ended are not replayable', () async {
    final requests = StreamController<int>();
    final log = RequestLog<int>(requests.stream);
    final subscription = log.next().listen((_) {});
    requests.add(1);
    await Future<void>.delayed(Duration.zero);

    expect(log.isReplayable, isFalse);
    await subscription.cancel();
    await requests.close();
  });

  test('two requests are not replayable', () async {
    final log = RequestLog<int>(Stream<int>.fromIterable([1, 2]));
    await log.next().toList();

    expect(log.isReplayable, isFalse);
  });

  test('requests never read are not replayable', () {
    final log = RequestLog<int>(Stream<int>.fromIterable([1]));

    expect(log.isReplayable, isFalse);
  });

  test('pause, resume and cancel reach the original requests', () async {
    final requests = StreamController<int>();
    var cancelled = false;
    requests.onCancel = () => cancelled = true;
    final subscription = RequestLog<int>(
      requests.stream,
    ).next().listen((_) {});

    subscription.pause();
    expect(requests.isPaused, isTrue);
    subscription.resume();
    expect(requests.isPaused, isFalse);
    await subscription.cancel();
    expect(cancelled, isTrue);
    await requests.close();
  });
}
