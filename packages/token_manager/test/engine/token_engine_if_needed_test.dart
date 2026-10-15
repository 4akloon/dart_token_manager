import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/refresh_failure.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';

void main() {
  const ahead = Duration(minutes: 5);
  // Between the 30 second skew and the 5 minute window.
  const inWindow = Duration(minutes: 3);
  // Assigned in setUp, which runs before every test.
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('completes without a refresh when enough time is left', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(hours: 1)));

    await engine.refreshIfNeeded();

    expect(fixture.refresher.callCount, 0);
  });

  test(
    'completes without a session and without calling the refresher',
    () async {
      final engine = fixture.engine();

      await engine.refreshIfNeeded();

      expect(fixture.refresher.callCount, 0);
      expect(engine.state, isA<Unauthenticated<TokenSet>>());
    },
  );

  test('completes without a refresher', () async {
    final engine = fixture.engine(withRefresher: false);
    await engine.setTokens(fixture.tokens(const Duration(seconds: 5)));

    await engine.refreshIfNeeded();

    expect(fixture.refresher.callCount, 0);
  });

  test('awaits the refresh of tokens inside the skew', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    var done = false;

    final pending = engine.refreshIfNeeded().then((_) => done = true);
    await settle();
    expect(done, isFalse);
    fixture.refresher.complete(fresh);
    await pending;

    expect(fixture.store.stored, same(fresh));
    expect(engine.state.tokensOrNull, same(fresh));
    expect(fixture.refresher.callCount, 1);
  });

  test('loads the stored tokens first', () async {
    final stored = fixture.tokens(const Duration(seconds: 10));
    fixture.store.stored = stored;
    final engine = fixture.engine();

    final pending = engine.refreshIfNeeded();
    await settle();

    expect(fixture.refresher.callCount, 1);
    expect(fixture.refresher.requested.single, same(stored));
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await pending;
  });

  test('joins the refresh in flight', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final blocking = engine.validToken();
    final explicit = engine.refreshIfNeeded();
    await settle();
    fixture.refresher.complete(fresh);

    expect(await blocking, same(fresh));
    await explicit;
    expect(fixture.refresher.callCount, 1);
  });

  test('joins a background refresh', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    await engine.validToken();

    final explicit = engine.refreshIfNeeded();
    await settle();
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await explicit;

    expect(fixture.refresher.callCount, 1);
  });

  test('throws InvalidGrant and ends the session', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));

    final failed = expectLater(
      engine.refreshIfNeeded(),
      throwsA(isA<InvalidGrant>()),
    );
    await settle();
    fixture.refresher.fail(const InvalidGrant());
    await failed;

    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('throws Transient and keeps the session', () async {
    final engine = fixture.engine();
    final current = fixture.tokens(const Duration(seconds: 10));
    await engine.setTokens(current);

    final failed = expectLater(
      engine.refreshIfNeeded(),
      throwsA(isA<Transient>()),
    );
    await settle();
    fixture.refresher.fail(const Transient('offline'));
    await failed;

    expect(engine.state, isA<Authenticated<TokenSet>>());
    expect(engine.state.tokensOrNull, same(current));
  });

  test('completes when a logout supersedes the refresh', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));

    final pending = engine.refreshIfNeeded();
    await settle();
    await engine.logout();
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await pending;

    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('within larger than the default refreshes earlier', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(minutes: 5)));

    await engine.refreshIfNeeded();
    expect(fixture.refresher.callCount, 0);

    final pending = engine.refreshIfNeeded(within: const Duration(minutes: 10));
    await settle();
    expect(fixture.refresher.callCount, 1);
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await pending;
  });

  test('within defaults to refreshAhead when it is set', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));

    final pending = engine.refreshIfNeeded();
    await settle();

    expect(fixture.refresher.callCount, 1);
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await pending;
  });

  test('within defaults to the skew without refreshAhead', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(inWindow));

    await engine.refreshIfNeeded();

    expect(fixture.refresher.callCount, 0);
  });

  test('refreshes tokens a failed background attempt left behind', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    await engine.validToken();
    fixture.refresher.fail(const Transient('offline'));
    await settle();
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final explicit = engine.refreshIfNeeded();
    await settle();
    fixture.refresher.complete(fresh, call: 1);
    await explicit;

    expect(fixture.refresher.callCount, 2);
    expect(engine.state.tokensOrNull, same(fresh));
  });
}
