import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/refresh_on_resume.dart'
    show ResumeRefresh, StandInRefresher;
import '../helpers/fake_clock.dart';

void main() {
  final clock = FakeClock(DateTime.utc(2026));

  TokenSet tokensExpiringIn(Duration life) => TokenSet(
    accessToken: 'access-0',
    refreshToken: 'refresh-0',
    expiresAt: clock.now().add(life),
  );

  TokenManager<TokenSet> managerWith(StandInRefresher refresher) {
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(),
      refresher: refresher,
      info: const TokenSetInfo(),
      refreshAhead: const Duration(minutes: 5),
      clock: clock,
    );
    addTearDown(manager.dispose);
    return manager;
  }

  test(
    'tokens with less than ten minutes left are refreshed on resume',
    () async {
      final refresher = StandInRefresher(clock: clock);
      final manager = managerWith(refresher);
      await manager.setTokens(tokensExpiringIn(const Duration(minutes: 8)));

      await ResumeRefresh(manager).onResumed();

      expect(refresher.calls, 1);
      expect((await manager.current())?.accessToken, 'access-1');
    },
  );

  test('tokens with plenty of time left are not refreshed', () async {
    final refresher = StandInRefresher(clock: clock);
    final manager = managerWith(refresher);
    await manager.setTokens(tokensExpiringIn(const Duration(hours: 1)));

    await ResumeRefresh(manager).onResumed();

    expect(refresher.calls, 0);
    expect((await manager.current())?.accessToken, 'access-0');
  });

  test('a signed-out app does nothing on resume', () async {
    final refresher = StandInRefresher(clock: clock);
    final manager = managerWith(refresher);

    await ResumeRefresh(manager).onResumed();

    expect(refresher.calls, 0);
    expect(await manager.current(), isNull);
  });

  test('an offline resume keeps the session and does not throw', () async {
    final refresher = StandInRefresher(
      clock: clock,
      failure: const Transient('offline'),
    );
    final manager = managerWith(refresher);
    await manager.setTokens(tokensExpiringIn(const Duration(minutes: 8)));

    await ResumeRefresh(manager).onResumed();

    expect(refresher.calls, 1);
    expect((await manager.current())?.accessToken, 'access-0');
  });

  test('a dead refresh token signs out on resume without throwing', () async {
    final refresher = StandInRefresher(
      clock: clock,
      failure: const InvalidGrant(),
    );
    final manager = managerWith(refresher);
    await manager.setTokens(tokensExpiringIn(const Duration(minutes: 8)));

    await ResumeRefresh(manager).onResumed();

    expect(await manager.current(), isNull);
  });

  test('two resumes at once share one refresh', () async {
    final refresher = StandInRefresher(clock: clock);
    final manager = managerWith(refresher);
    await manager.setTokens(tokensExpiringIn(const Duration(minutes: 8)));
    final resume = ResumeRefresh(manager);

    await Future.wait([resume.onResumed(), resume.onResumed()]);

    expect(refresher.calls, 1);
  });
}
