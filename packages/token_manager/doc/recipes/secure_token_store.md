# Recipe: keep the session in secure storage

Make the session survive a restart of the app by writing the tokens to secure
storage (Keychain, Keystore) through a custom `TokenStore`. Use this when the
user must stay signed in after the process ends.

## The code

`SecretBox` is the three-method key-value box you back with the secure-storage
plugin of your platform. `SecureTokenStore` stores a `TokenSet` in it as JSON.
`MemorySecretBox` stands in for the plugin so the file runs anywhere.

<!-- include: example/recipes/secure_token_store.dart -->
```dart
import 'dart:convert';
import 'dart:io';

import 'package:token_manager/token_manager.dart';

/// A key-value box in secure storage (Keychain, Keystore); implement it with
/// the secure-storage plugin of your platform.
abstract interface class SecretBox {
  /// Returns the value of [key], or `null`.
  Future<String?> read(String key);

  /// Stores [value] under [key].
  Future<void> write(String key, String value);

  /// Removes [key].
  Future<void> delete(String key);
}

/// Keeps a `TokenSet` as JSON in a [SecretBox], so the session survives a
/// restart of the app.
final class SecureTokenStore implements TokenStore<TokenSet> {
  /// Creates a store over [_box].
  const SecureTokenStore(this._box);

  static const String _key = 'auth.tokens';

  final SecretBox _box;

  @override
  Future<TokenSet?> read() async {
    final raw = await _box.read(_key);
    return raw == null ? null : _decode(raw);
  }

  @override
  Future<void> write(TokenSet tokens) {
    return _box.write(
      _key,
      jsonEncode({
        'accessToken': tokens.accessToken,
        'refreshToken': tokens.refreshToken,
        'expiresAt': tokens.expiresAt?.toIso8601String(),
      }),
    );
  }

  @override
  Future<void> delete() => _box.delete(_key);

  /// Returns `null` for a payload that cannot be read, so a damaged entry
  /// means "signed out" and the next sign-in replaces it.
  TokenSet? _decode(String raw) {
    try {
      return switch (jsonDecode(raw)) {
        {
          'accessToken': final String access,
          'refreshToken': final String? refresh,
          'expiresAt': final String? expires,
        } =>
          TokenSet(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expires == null ? null : DateTime.parse(expires),
          ),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }
}

// ---- Stand-in for secure storage, so this file runs without a device.

/// A [SecretBox] that keeps its values in a map.
final class MemorySecretBox implements SecretBox {
  /// The stored values by key.
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

Future<void> main() async {
  final box = MemorySecretBox();

  final first = TokenManager<TokenSet>.create(
    store: SecureTokenStore(box),
    info: const TokenSetInfo(),
  );
  await first.setTokens(
    TokenSet(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );
  await first.dispose();

  // A new manager over the same box, as after a restart of the app.
  final second = TokenManager<TokenSet>.create(
    store: SecureTokenStore(box),
    info: const TokenSetInfo(),
  );
  stdout.writeln('Restored: ${(await second.current())?.accessToken}');
  await second.dispose();
}
```

Run it with `dart run example/recipes/secure_token_store.dart`. The test
`test/recipes/secure_token_store_test.dart` checks every behaviour below.

## What you get

- A new manager over the same box finds the tokens again: the manager reads the
  store lazily, on the first `current`, `validToken` or `authorize`.
- `setTokens` publishes the tokens to `states` only after `write` succeeded.
- `logout` and a dead refresh token call `delete`, so the box is empty.
- A damaged or unknown entry reads as signed out, and the next sign-in replaces
  it.

## Common mistakes

- **Using plain preferences or a file.** Those are not encrypted; keep tokens in
  secure storage.
- **Looking for an `initialize()` step.** There is none; loading is lazy.
- **Swallowing every exception in `read`.** A `read` that throws fails the
  call that triggered the load, and the next call retries. Return `null` only
  for data you know is unreadable, as `_decode` does.
- **Expecting a failed write after a refresh to be reported.** The server has
  already rotated the old pair, so the refreshed tokens stay in memory until
  the next write; see the storage guide.
- **Sharing one key between users.** Use one key per signed-in account, or
  delete the entry on sign-out.

## See also

- [Storage guide](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/storage.md)
