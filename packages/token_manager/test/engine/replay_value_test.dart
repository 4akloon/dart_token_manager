import 'package:test/test.dart';
import 'package:token_manager/src/engine/replay_value.dart';

void main() {
  test('a listener gets the current value first', () async {
    final replay = ReplayValue<int>(1);

    await expectLater(replay.stream, emits(1));
  });

  test('a late listener gets the last value, then later ones', () async {
    final replay = ReplayValue<int>(1)..add(2);
    final seen = expectLater(replay.stream, emitsInOrder([2, 3]));

    replay.add(3);

    await seen;
  });

  test('two listeners are independent', () async {
    final replay = ReplayValue<int>(1);
    final first = expectLater(replay.stream, emitsInOrder([1, 2]));
    final second = expectLater(replay.stream, emitsInOrder([1, 2]));

    replay.add(2);

    await first;
    await second;
  });

  test('value reflects the last added value', () {
    final replay = ReplayValue<int>(1)..add(5);

    expect(replay.value, 5);
  });

  test('the stream completes after close', () async {
    final replay = ReplayValue<int>(1);
    final seen = expectLater(replay.stream, emitsInOrder([1, emitsDone]));

    await replay.close();

    await seen;
  });

  test('adding after close is ignored', () async {
    final replay = ReplayValue<int>(1);
    await replay.close();

    replay.add(2);

    expect(replay.value, 1);
  });
}
