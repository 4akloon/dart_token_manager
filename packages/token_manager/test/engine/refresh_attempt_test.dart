import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/engine/refresh_attempt.dart';
import 'package:token_manager/src/engine/session.dart';
import 'package:token_manager/src/not_authenticated.dart';
import 'package:token_manager/src/refresh_failure.dart';

import '../helpers/fake_refresher.dart';
import '../helpers/fake_token_store.dart';

void main() {
  late Session<String> session;
  late FakeTokenStore<String> store;
  late FakeRefresher<String> refresher;

  setUp(() {
    session = Session<String>()..emit(const Authenticated<String>('old'));
    store = FakeTokenStore<String>();
    refresher = FakeRefresher<String>();
  });

  Future<String> start() {
    return RefreshAttempt<String>(
      session: session,
      store: store,
      refresher: refresher,
      current: 'old',
    ).run();
  }

  test('run emits Refreshing before the refresher answers', () async {
    final result = start();

    expect(session.state, isA<Refreshing<String>>());

    refresher.complete('new');
    await result;
  });

  test('run persists and emits the refreshed tokens', () async {
    final result = start();
    refresher.complete('new');

    expect(await result, 'new');
    expect(store.stored, 'new');
    expect(session.state, isA<Authenticated<String>>());
    expect(session.state.tokensOrNull, 'new');
  });

  test('a failed write keeps the refreshed tokens in memory', () async {
    store.writeError = Exception('disk');
    final result = start();
    refresher.complete('new');

    expect(await result, 'new');
    expect(session.state.tokensOrNull, 'new');
  });

  test('a transient failure restores the old tokens and throws', () async {
    final result = start();
    final failed = expectLater(result, throwsA(isA<Transient>()));
    refresher.fail(Exception('net'));

    await failed;
    expect(session.state.tokensOrNull, 'old');
  });

  test('an Error leaves the state on the old tokens', () async {
    final result = start();
    final failed = expectLater(result, throwsStateError);
    refresher.fail(StateError('bug'));

    await failed;
    expect(session.state, isA<Authenticated<String>>());
    expect(session.state.tokensOrNull, 'old');
  });

  test('InvalidGrant ends the session even if delete fails', () async {
    store.deleteError = Exception('disk');
    final result = start();
    final failed = expectLater(result, throwsA(isA<InvalidGrant>()));
    refresher.fail(const InvalidGrant());

    await failed;
    expect(session.state, isA<Unauthenticated<String>>());
    expect(session.epoch, 1);
  });

  test('a refresh superseded by a new session is discarded', () async {
    final result = start();
    session
      ..startNewSession()
      ..emit(const Authenticated<String>('set'));

    refresher.complete('new');

    expect(await result, 'set');
    expect(store.writes, 0);
    expect(session.state.tokensOrNull, 'set');
  });

  test('a superseded failure resolves with the new session tokens', () async {
    final result = start();
    session
      ..startNewSession()
      ..emit(const Authenticated<String>('set'));

    refresher.fail(Exception('net'));

    expect(await result, 'set');
  });

  test('a superseded refresh into logout throws NotAuthenticated', () async {
    final result = start();
    final failed = expectLater(result, throwsA(isA<NotAuthenticated>()));
    session
      ..startNewSession()
      ..emit(const Unauthenticated<String>());

    refresher.complete('new');

    await failed;
  });

  test('a refresh finishing after close is still persisted', () async {
    final result = start();
    await session.close();

    refresher.complete('new');

    expect(await result, 'new');
    expect(store.stored, 'new');
    expect(session.state.tokensOrNull, 'new');
  });
}
