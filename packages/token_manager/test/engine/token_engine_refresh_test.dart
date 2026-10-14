import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/not_authenticated.dart';
import 'package:token_manager/src/refresh_failure.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';

void main() {
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('refreshes tokens inside the skew and persists the result', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final pending = engine.validToken();
    await settle();
    fixture.refresher.complete(fresh);

    expect(await pending, same(fresh));
    expect(fixture.store.stored, same(fresh));
    expect(engine.state, isA<Authenticated<TokenSet>>());
  });

  test('emits Refreshing while a refresh runs', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));

    final pending = engine.validToken();
    await settle();

    expect(engine.state, isA<Refreshing<TokenSet>>());
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await pending;
  });

  test('concurrent callers share one refresh', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final first = engine.validToken();
    final second = engine.validToken();
    await settle();
    fixture.refresher.complete(fresh);

    expect(fixture.refresher.callCount, 1);
    expect(await first, same(fresh));
    expect(await second, same(fresh));
  });

  test(
    'a rejected current token is refreshed even if it looks valid',
    () async {
      final engine = fixture.engine();
      final current = fixture.tokens(const Duration(hours: 1));
      await engine.setTokens(current);
      final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

      final pending = engine.validToken(rejected: current);
      await settle();
      fixture.refresher.complete(fresh);

      expect(await pending, same(fresh));
      expect(fixture.refresher.requested.single, same(current));
    },
  );

  test('a rejected token that is no longer current does not refresh', () async {
    final engine = fixture.engine();
    final current = fixture.tokens(const Duration(hours: 1));
    await engine.setTokens(current);
    final old = fixture.tokens(const Duration(hours: 1), access: 'old');

    expect(await engine.validToken(rejected: old), same(current));
    expect(fixture.refresher.callCount, 0);
  });

  test('without a refresher the tokens are returned as they are', () async {
    final engine = fixture.engine(withRefresher: false);
    final expiring = fixture.tokens(const Duration(seconds: 1));
    await engine.setTokens(expiring);

    expect(await engine.validToken(rejected: expiring), same(expiring));
  });

  test('InvalidGrant clears the session and fails every waiter', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));

    final first = expectLater(
      engine.validToken(),
      throwsA(isA<InvalidGrant>()),
    );
    final second = expectLater(
      engine.validToken(),
      throwsA(isA<InvalidGrant>()),
    );
    await settle();
    fixture.refresher.fail(const InvalidGrant());
    await first;
    await second;

    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('Transient keeps the session and the next call retries', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(seconds: 10));
    await engine.setTokens(old);

    final failed = expectLater(
      engine.validToken(),
      throwsA(isA<Transient>()),
    );
    await settle();
    fixture.refresher.fail(const Transient('offline'));
    await failed;

    expect(fixture.store.deletes, 0);
    expect(engine.state.tokensOrNull, same(old));
    final retry = engine.validToken();
    await settle();
    expect(fixture.refresher.callCount, 2);
    fixture.refresher.complete(
      fixture.tokens(const Duration(hours: 1)),
      call: 1,
    );
    await retry;
  });

  test('an exception that is not a RefreshFailure is transient', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(seconds: 10));
    await engine.setTokens(old);

    final failed = expectLater(
      engine.validToken(),
      throwsA(
        isA<Transient>().having(
          (failure) => failure.cause,
          'cause',
          isA<FormatException>(),
        ),
      ),
    );
    await settle();
    fixture.refresher.fail(const FormatException('bad body'));
    await failed;

    expect(fixture.store.deletes, 0);
    expect(engine.state.tokensOrNull, same(old));
  });

  test(
    'a refreshed token already inside the skew is returned, not looped on',
    () async {
      final engine = fixture.engine();
      await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
      final shortLived = fixture.tokens(
        const Duration(seconds: 5),
        access: 'b',
      );

      final pending = engine.validToken().timeout(const Duration(seconds: 2));
      await settle();
      fixture.refresher.complete(shortLived);

      expect(await pending, same(shortLived));
      expect(fixture.refresher.callCount, 1);
    },
  );

  test('setTokens during a refresh discards the refresh result', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final loggedIn = fixture.tokens(const Duration(hours: 2), access: 'login');

    final pending = engine.validToken();
    await settle();
    await engine.setTokens(loggedIn);
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));

    expect(await pending, same(loggedIn));
    expect(fixture.store.stored, same(loggedIn));
  });

  test('logout during a refresh discards the refresh result', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));

    final pending = expectLater(
      engine.validToken(),
      throwsA(isA<NotAuthenticated>()),
    );
    await settle();
    await engine.logout();
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await pending;

    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('a refresh completing after dispose is still persisted', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(seconds: 10));
    await engine.setTokens(old);
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final pending = engine.validToken();
    await settle();
    await engine.dispose();
    fixture.refresher.complete(fresh);

    expect(await pending, same(fresh));
    expect(fixture.store.stored, same(fresh));
  });

  test('a failed write keeps the refreshed tokens in memory', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    fixture.store.writeError = Exception('disk full');

    final pending = engine.validToken();
    await settle();
    fixture.refresher.complete(fresh);

    expect(await pending, same(fresh));
    expect(engine.state, isA<Authenticated<TokenSet>>());
    expect(engine.state.tokensOrNull, same(fresh));
    expect(fixture.refresher.callCount, 1);
  });

  test('a waiter that gives up does not cancel the shared refresh', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final impatient = expectLater(
      engine.validToken().timeout(const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
    final patient = engine.validToken();
    await impatient;
    fixture.refresher.complete(fresh);

    expect(await patient, same(fresh));
  });

  test(
    'pendingRefresh is null when idle and completes with the refresh',
    () async {
      final engine = fixture.engine();
      await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
      expect(engine.pendingRefresh, isNull);

      final refresh = engine.validToken();
      await settle();
      final pending = engine.pendingRefresh;
      expect(pending, isNotNull);

      fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
      await refresh;
      await pending;
      expect(engine.pendingRefresh, isNull);
    },
  );
}
