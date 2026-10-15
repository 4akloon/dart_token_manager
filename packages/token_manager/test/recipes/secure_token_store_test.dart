import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/secure_token_store.dart'
    show MemorySecretBox, SecretBox, SecureTokenStore;

void main() {
  // Assigned in setUp, which runs before every test.
  late MemorySecretBox box;
  late SecureTokenStore store;
  final tokens = TokenSet(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: DateTime.utc(2030),
  );

  setUp(() {
    box = MemorySecretBox();
    store = SecureTokenStore(box);
  });

  test('read returns null when nothing is stored', () async {
    expect(await store.read(), isNull);
  });

  test('write then read returns the same tokens', () async {
    await store.write(tokens);

    expect(await store.read(), tokens);
  });

  test(
    'tokens without a refresh token or expiry survive a round trip',
    () async {
      const bare = TokenSet(accessToken: 'access');

      await store.write(bare);

      expect(await store.read(), bare);
    },
  );

  test('delete removes the entry from the box', () async {
    await store.write(tokens);

    await store.delete();

    expect(box.values, isEmpty);
  });

  test('a damaged entry reads as signed out', () async {
    box.values['auth.tokens'] = '{not json';

    expect(await store.read(), isNull);
  });

  test('an entry with the wrong shape reads as signed out', () async {
    box.values['auth.tokens'] = '{"accessToken": 1}';

    expect(await store.read(), isNull);
  });

  test('a new manager restores the session after a restart', () async {
    final first = TokenManager<TokenSet>.create(store: store);
    await first.setTokens(tokens);
    await first.dispose();

    final second = TokenManager<TokenSet>.create(
      store: SecureTokenStore(box),
    );

    expect(await second.current(), tokens);
    await second.dispose();
  });

  test('logout empties the box', () async {
    final manager = TokenManager<TokenSet>.create(store: store);
    await manager.setTokens(tokens);

    await manager.logout();

    expect(box.values, isEmpty);
    await manager.dispose();
  });

  test('a failed write leaves the manager signed out and silent', () async {
    final manager = TokenManager<TokenSet>.create(
      store: SecureTokenStore(_FailingWriteBox()),
    );
    addTearDown(manager.dispose);
    final published = <AuthState<TokenSet>>[];
    final subscription = manager.states.listen(published.add);
    addTearDown(subscription.cancel);

    await expectLater(manager.setTokens(tokens), throwsStateError);
    await pumpEventQueue();

    expect(await manager.current(), isNull);
    // The stream replays the current state on listen; nothing newer follows.
    expect(published, everyElement(isA<Unauthenticated<TokenSet>>()));
  });

  test('a dead refresh token deletes the entry from the box', () async {
    final manager = TokenManager<TokenSet>.create(
      store: store,
      refresher: _DeadRefresher(),
    );
    addTearDown(manager.dispose);
    await manager.setTokens(tokens);

    await expectLater(
      manager.validToken(rejected: tokens),
      throwsA(isA<InvalidGrant>()),
    );

    expect(box.values, isEmpty);
  });
}

/// A box whose writes always fail.
final class _FailingWriteBox implements SecretBox {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {
    throw StateError('keychain locked');
  }

  @override
  Future<void> delete(String key) async {}
}

/// A refresher whose refresh token is always rejected.
final class _DeadRefresher implements TokenRefresher<TokenSet> {
  @override
  Future<TokenSet> refresh(TokenSet current) async {
    throw const InvalidGrant();
  }
}
