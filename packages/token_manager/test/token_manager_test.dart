import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/fake_clock.dart';
import 'helpers/fake_refresher.dart';
import 'helpers/fake_token_store.dart';

final class _Unauthorized implements Exception {
  const _Unauthorized();
}

void main() {
  late FakeClock clock;
  late FakeTokenStore<TokenSet> store;
  late FakeRefresher<TokenSet> refresher;
  late TokenManager<TokenSet> manager;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  TokenSet tokens(Duration life, {String access = 'a'}) => TokenSet(
    accessToken: access,
    expiresAt: clock.now().add(life),
  );

  setUp(() {
    clock = FakeClock(DateTime.utc(2026));
    store = FakeTokenStore<TokenSet>();
    refresher = FakeRefresher<TokenSet>();
    manager = TokenManager<TokenSet>.create(
      store: store,
      refresher: refresher,
      info: const TokenSetInfo(),
      clock: clock,
    );
  });

  test('states replays Unauthenticated and then follows setTokens', () async {
    final seen = expectLater(
      manager.states,
      emitsInOrder([
        isA<Unauthenticated<TokenSet>>(),
        isA<Authenticated<TokenSet>>(),
      ]),
    );

    await manager.setTokens(tokens(const Duration(hours: 1)));

    await seen;
  });

  test('setTokens with null logs out', () async {
    await manager.setTokens(tokens(const Duration(hours: 1)));

    await manager.setTokens(null);

    expect(store.stored, isNull);
    expect(await manager.current(), isNull);
  });

  test('logout clears the session', () async {
    await manager.setTokens(tokens(const Duration(hours: 1)));

    await manager.logout();

    expect(await manager.current(), isNull);
  });

  test('authorize replays once with refreshed tokens', () async {
    final old = tokens(const Duration(hours: 1));
    await manager.setTokens(old);
    final sent = <TokenSet>[];

    final result = manager.authorize<String>((used) async {
      sent.add(used);
      if (identical(used, old)) {
        throw const _Unauthorized();
      }
      return 'ok';
    }, isAuthFailure: (error) => error is _Unauthorized);
    await settle();
    refresher.complete(tokens(const Duration(hours: 1), access: 'b'));

    expect(await result, 'ok');
    expect(sent, hasLength(2));
  });

  test('authorizeStream opens the source with valid tokens', () async {
    await manager.setTokens(tokens(const Duration(hours: 1), access: 'live'));

    final received = await manager
        .authorizeStream<String>(
          (used) => Stream.value(used.accessToken),
          isAuthFailure: (error) => error is _Unauthorized,
        )
        .toList();

    expect(received, ['live']);
  });

  test('a manager without a refresher never refreshes', () async {
    final plain = TokenManager<TokenSet>.create(store: store, clock: clock);
    final expiring = tokens(const Duration(seconds: 1));
    await plain.setTokens(expiring);

    expect(await plain.validToken(), same(expiring));
  });

  test('create rejects a refreshAhead that equals the skew', () {
    expect(
      () => TokenManager<TokenSet>.create(
        store: store,
        refreshAhead: const Duration(seconds: 30),
      ),
      throwsArgumentError,
    );
  });

  test('create checks refreshAhead against a custom skew', () {
    expect(
      () => TokenManager<TokenSet>.create(
        store: store,
        skew: const Duration(minutes: 2),
        refreshAhead: const Duration(seconds: 90),
      ),
      throwsArgumentError,
    );
  });

  test('create accepts a refreshAhead greater than the skew', () {
    expect(
      () => TokenManager<TokenSet>.create(
        store: store,
        refreshAhead: const Duration(minutes: 5),
      ),
      returnsNormally,
    );
  });

  test('create with refreshAhead refreshes close-to-expiry tokens in the '
      'background', () async {
    final eager = TokenManager<TokenSet>.create(
      store: store,
      refresher: refresher,
      info: const TokenSetInfo(),
      refreshAhead: const Duration(minutes: 5),
      clock: clock,
    );
    final soon = tokens(const Duration(minutes: 3));
    await eager.setTokens(soon);

    expect(await eager.validToken(), same(soon));
    expect(refresher.callCount, 1);
  });

  test(
    'refreshIfNeeded refreshes tokens that expire within the window',
    () async {
      await manager.setTokens(tokens(const Duration(minutes: 3)));

      final pending = manager.refreshIfNeeded(
        within: const Duration(minutes: 5),
      );
      await settle();
      refresher.complete(tokens(const Duration(hours: 1), access: 'b'));
      await pending;

      expect((await manager.current())?.accessToken, 'b');
    },
  );

  test('refreshIfNeeded does nothing when signed out', () async {
    await manager.refreshIfNeeded();

    expect(refresher.callCount, 0);
  });
}
