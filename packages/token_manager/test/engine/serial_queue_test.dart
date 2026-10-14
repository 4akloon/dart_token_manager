import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager/src/engine/serial_queue.dart';

void main() {
  test('actions run in the order they were queued', () async {
    final queue = SerialQueue();
    final order = <int>[];

    final first = queue.run<void>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      order.add(1);
    });
    final second = queue.run<void>(() async => order.add(2));
    await Future.wait([first, second]);

    expect(order, [1, 2]);
  });

  test(
    'an action does not start before the previous one has finished',
    () async {
      final queue = SerialQueue();
      final gate = Completer<void>();
      var secondStarted = false;

      final first = queue.run<void>(() => gate.future);
      final second = queue.run<void>(() async => secondStarted = true);
      await Future<void>.delayed(Duration.zero);

      expect(secondStarted, isFalse);
      gate.complete();
      await Future.wait([first, second]);
      expect(secondStarted, isTrue);
    },
  );

  test('run completes with the result of the action', () async {
    final queue = SerialQueue();

    expect(await queue.run<int>(() async => 7), 7);
  });

  test('run completes with the error of the action', () async {
    final queue = SerialQueue();

    await expectLater(
      queue.run<void>(() async => throw StateError('boom')),
      throwsStateError,
    );
  });

  test('a failed action does not block the next one', () async {
    final queue = SerialQueue();
    final failed = queue.run<void>(() async => throw StateError('boom'));
    final next = queue.run<int>(() async => 2);

    await expectLater(failed, throwsStateError);
    expect(await next, 2);
  });

  test('an action queued after the queue went idle still runs', () async {
    final queue = SerialQueue();
    await queue.run<void>(() async {});

    expect(await queue.run<int>(() async => 3), 3);
  });
}
