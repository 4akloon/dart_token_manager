import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/engine/session.dart';

void main() {
  late Session<String> session;

  setUp(() => session = Session<String>());

  test('starts unauthenticated in epoch 0 with no flight', () {
    expect(session.state, isA<Unauthenticated<String>>());
    expect(session.epoch, 0);
    expect(session.flight, isNull);
  });

  test('emit updates the state and notifies listeners', () async {
    final seen = <AuthState<String>>[];
    final subscription = session.states.listen(seen.add);
    await Future<void>.delayed(Duration.zero);

    session.emit(const Authenticated<String>('a'));
    await Future<void>.delayed(Duration.zero);

    expect(session.state.tokensOrNull, 'a');
    expect(seen.last.tokensOrNull, 'a');
    await subscription.cancel();
  });

  test('startNewSession bumps the epoch and drops the flight', () {
    session.track(Completer<String>().future);

    session.startNewSession();

    expect(session.epoch, 1);
    expect(session.flight, isNull);
  });

  test('track keeps the flight until it completes', () async {
    final flight = Completer<String>();
    session.track(flight.future);
    expect(session.flight, same(flight.future));

    flight.complete('a');
    await Future<void>.delayed(Duration.zero);

    expect(session.flight, isNull);
  });

  test('track forgets a flight that fails', () async {
    final flight = Completer<String>();
    session.track(flight.future);
    final failed = expectLater(flight.future, throwsException);

    flight.completeError(Exception('x'));
    await failed;
    await Future<void>.delayed(Duration.zero);

    expect(session.flight, isNull);
  });

  test('an old flight ending does not clear a newer one', () async {
    final old = Completer<String>();
    final newer = Completer<String>();
    session.track(old.future);
    session.startNewSession();
    session.track(newer.future);

    old.complete('a');
    await Future<void>.delayed(Duration.zero);

    expect(session.flight, same(newer.future));
  });

  test('state keeps following emit after close', () async {
    await session.close();

    session.emit(const Authenticated<String>('a'));

    expect(session.state.tokensOrNull, 'a');
  });

  test('isClosed follows close', () async {
    expect(session.isClosed, isFalse);

    await session.close();

    expect(session.isClosed, isTrue);
  });
}
