import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/testing_without_network.dart';

void main() {
  // Assigned in setUp, which runs before every test.
  late FixedClock clock;

  TokenManager<TokenSet> managerFor(
    CountingRefresher refresher,
    Duration life,
  ) {
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(
        TokenSet(
          accessToken: 'stale',
          refreshToken: 'refresh',
          expiresAt: clock.current.add(life),
        ),
      ),
      refresher: refresher,
      info: const TokenSetInfo(),
      clock: clock,
    );
    addTearDown(manager.dispose);
    return manager;
  }

  setUp(() => clock = FixedClock(DateTime.utc(2026)));

  test('tokens inside the skew are refreshed before the call', () async {
    final refresher = CountingRefresher();
    final api = FakeProfileApi({'fresh-1'});
    final repository = ProfileRepository(
      managerFor(refresher, const Duration(seconds: 10)),
      api,
    );

    await repository.load();

    expect(api.seen, ['fresh-1']);
    expect(refresher.calls, 1);
  });

  test('valid tokens are sent without a refresh', () async {
    final refresher = CountingRefresher();
    final api = FakeProfileApi({'stale'});
    final repository = ProfileRepository(
      managerFor(refresher, const Duration(hours: 1)),
      api,
    );

    await repository.load();

    expect(api.seen, ['stale']);
    expect(refresher.calls, 0);
  });

  test('a rejected token is refreshed and the call replayed once', () async {
    final refresher = CountingRefresher();
    final api = FakeProfileApi({'fresh-1'});
    final repository = ProfileRepository(
      managerFor(refresher, const Duration(hours: 1)),
      api,
    );

    await repository.load();

    expect(api.seen, ['stale', 'fresh-1']);
    expect(refresher.calls, 1);
  });

  test('a dead refresh token fails the call and signs out', () async {
    final manager = managerFor(
      CountingRefresher(failure: const InvalidGrant()),
      const Duration(hours: 1),
    );
    final repository = ProfileRepository(manager, FakeProfileApi({'fresh-1'}));

    await expectLater(repository.load(), throwsA(isA<InvalidGrant>()));

    expect(await manager.current(), isNull);
  });

  test('moving the clock past the expiry triggers a refresh', () async {
    final refresher = CountingRefresher();
    final repository = ProfileRepository(
      managerFor(refresher, const Duration(hours: 1)),
      FakeProfileApi({'stale', 'fresh-1'}),
    );
    await repository.load();
    expect(refresher.calls, 0);

    clock.current = clock.current.add(const Duration(hours: 1));
    await repository.load();

    expect(refresher.calls, 1);
  });
}
