import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/session_expiry.dart'
    show RevokedRefresher, SessionWatcher;
import '../helpers/fake_clock.dart';

final class _TransientRefresher implements TokenRefresher<TokenSet> {
  const _TransientRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    throw const Transient('offline');
  }
}

void main() {
  final clock = FakeClock(DateTime.utc(2026));
  // Assigned in setUp, which runs before every test.
  late int signedOut;

  TokenSet expiring() => TokenSet(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: clock.now().add(const Duration(seconds: 5)),
  );

  TokenManager<TokenSet> managerWith(TokenRefresher<TokenSet> refresher) =>
      TokenManager<TokenSet>.create(
        store: InMemoryTokenStore<TokenSet>(),
        refresher: refresher,
        info: const TokenSetInfo(),
        clock: clock,
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() => signedOut = 0);

  test('an app that starts signed out is not reported', () async {
    final manager = managerWith(const RevokedRefresher());
    final watcher = SessionWatcher(manager)
      ..watch(onSignedOut: () => signedOut++);

    await settle();

    expect(signedOut, 0);
    await watcher.close();
    await manager.dispose();
  });

  test('a rejected refresh token reports the end of the session', () async {
    final manager = managerWith(const RevokedRefresher());
    final watcher = SessionWatcher(manager)
      ..watch(onSignedOut: () => signedOut++);
    await manager.setTokens(expiring());

    await expectLater(manager.validToken(), throwsA(isA<InvalidGrant>()));
    await settle();

    expect(signedOut, 1);
    await watcher.close();
    await manager.dispose();
  });

  test('logout reports the end of the session once', () async {
    final manager = managerWith(const RevokedRefresher());
    final watcher = SessionWatcher(manager)
      ..watch(onSignedOut: () => signedOut++);
    await manager.setTokens(expiring());

    await manager.logout();
    await manager.logout();
    await settle();

    expect(signedOut, 1);
    await watcher.close();
    await manager.dispose();
  });

  test('a transient refresh failure keeps the session', () async {
    final manager = managerWith(const _TransientRefresher());
    final watcher = SessionWatcher(manager)
      ..watch(onSignedOut: () => signedOut++);
    await manager.setTokens(expiring());

    await expectLater(manager.validToken(), throwsA(isA<Transient>()));
    await settle();

    expect(signedOut, 0);
    expect(await manager.current(), isNotNull);
    await watcher.close();
    await manager.dispose();
  });
}
