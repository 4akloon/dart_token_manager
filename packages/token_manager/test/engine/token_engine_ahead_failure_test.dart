import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/refresh_failure.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';
import '../helpers/uncaught_errors.dart';

void main() {
  const ahead = Duration(minutes: 5);
  // Between the 30 second skew and the 5 minute window.
  const inWindow = Duration(minutes: 3);
  const watch = UncaughtErrors();
  // Assigned in setUp, which runs before every test.
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test(
    'a Transient background failure is swallowed, the session stays',
    () async {
      final engine = fixture.engine(refreshAhead: ahead);
      final current = fixture.tokens(inWindow);
      await engine.setTokens(current);

      final uncaught = await watch.during(() async {
        await engine.validToken();
        fixture.refresher.fail(const Transient('offline'));
        await settle();
      });

      expect(uncaught, isEmpty);
      expect(engine.state, isA<Authenticated<TokenSet>>());
      expect(engine.state.tokensOrNull, same(current));
      expect(fixture.store.deletes, 0);
    },
  );

  test(
    'a background failure that is not a RefreshFailure is swallowed',
    () async {
      final engine = fixture.engine(refreshAhead: ahead);
      final current = fixture.tokens(inWindow);
      await engine.setTokens(current);

      final uncaught = await watch.during(() async {
        await engine.validToken();
        fixture.refresher.fail(const FormatException('bad body'));
        await settle();
      });

      expect(uncaught, isEmpty);
      expect(engine.state, isA<Authenticated<TokenSet>>());
      expect(engine.state.tokensOrNull, same(current));
    },
  );

  test(
    'the same tokens get one background attempt, not one per call',
    () async {
      final engine = fixture.engine(refreshAhead: ahead);
      await engine.setTokens(fixture.tokens(inWindow));

      await watch.during(() async {
        await engine.validToken();
        fixture.refresher.fail(const Transient('offline'));
        await settle();
        await engine.validToken();
        await engine.validToken();
        await settle();
      });

      expect(fixture.refresher.callCount, 1);
    },
  );

  test('the same tokens set again after a logout are tried again', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);
    await watch.during(() async {
      await engine.validToken();
      fixture.refresher.fail(const Transient('offline'));
      await settle();
    });

    await engine.logout();
    await engine.setTokens(current);
    await watch.during(() async {
      await engine.validToken();
      await settle();
    });

    expect(fixture.refresher.callCount, 2);
  });

  test('the blocking path retries once the tokens reach the skew', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    await watch.during(() async {
      await engine.validToken();
      fixture.refresher.fail(const Transient('offline'));
      await settle();
    });
    fixture.clock.advance(const Duration(minutes: 2, seconds: 45));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final retry = engine.validToken();
    await settle();
    fixture.refresher.complete(fresh, call: 1);

    expect(await retry, same(fresh));
    expect(fixture.refresher.callCount, 2);
  });

  test('InvalidGrant in the background ends the session', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));

    final uncaught = await watch.during(() async {
      await engine.validToken();
      fixture.refresher.fail(const InvalidGrant());
      await settle();
    });

    expect(uncaught, isEmpty);
    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('a background failure that is not an Exception is swallowed', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);

    final uncaught = await watch.during(() async {
      await engine.validToken();
      fixture.refresher.fail('boom');
      await settle();
    });

    expect(uncaught, isEmpty);
    expect(engine.state, isA<Authenticated<TokenSet>>());
    expect(engine.state.tokensOrNull, same(current));
  });

  test('an Error from the refresher is not swallowed', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);

    final uncaught = await watch.during(() async {
      await engine.validToken();
      fixture.refresher.fail(StateError('bug in the refresher'));
      await settle();
    });

    expect(uncaught, hasLength(1));
    expect(uncaught.single, isA<StateError>());
    expect(engine.state, isA<Authenticated<TokenSet>>());
    expect(engine.state.tokensOrNull, same(current));
  });

  test('logout during the background refresh discards its result', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));

    final uncaught = await watch.during(() async {
      await engine.validToken();
      await engine.logout();
      fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
      await settle();
    });

    expect(uncaught, isEmpty);
    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('setTokens during the background refresh discards its result', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    final loggedIn = fixture.tokens(const Duration(hours: 2), access: 'login');

    final uncaught = await watch.during(() async {
      await engine.validToken();
      await engine.setTokens(loggedIn);
      fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
      await settle();
    });

    expect(uncaught, isEmpty);
    expect(fixture.store.stored, same(loggedIn));
    expect(engine.state.tokensOrNull, same(loggedIn));
  });

  test('no background refresh starts after dispose', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);
    await engine.dispose();

    expect(await engine.validToken(), same(current));
    await settle();

    expect(fixture.refresher.callCount, 0);
  });

  test('a background refresh running at dispose is still persisted', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    await engine.validToken();

    await engine.dispose();
    fixture.refresher.complete(fresh);
    await settle();

    expect(fixture.store.stored, same(fresh));
    expect(engine.state.tokensOrNull, same(fresh));
  });
}
