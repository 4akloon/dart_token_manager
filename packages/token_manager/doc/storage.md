# Storage

A `TokenStore<T>` persists the tokens of one session. The core does no
platform I/O itself, so the store is the place for secure storage.

```dart
import 'package:token_manager/token_manager.dart';

final store = InMemoryTokenStore<TokenSet>(
  TokenSet(accessToken: 'a', refreshToken: 'r'), // optional initial tokens
);
```

`TokenStore<T>` has three methods:

| Method | Contract |
|---|---|
| `Future<T?> read()` | The stored tokens, or `null` when there are none. |
| `Future<void> write(T tokens)` | Stores the tokens, replacing what was there. |
| `Future<void> delete()` | Removes the stored tokens. |

## InMemoryTokenStore

`InMemoryTokenStore<T>` keeps tokens in memory only. Use it in tests, or when a
session should end with the process.

## A secure-storage store

This one keeps a `TokenSet` as JSON in an abstract key-value `SecretBox`. Back
the box with `flutter_secure_storage` or your platform's keychain.

```dart
import 'dart:convert';

import 'package:token_manager/token_manager.dart';

abstract interface class SecretBox {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class SecureTokenStore implements TokenStore<TokenSet> {
  SecureTokenStore(this._box);

  static const _key = 'auth.tokens';
  final SecretBox _box;

  @override
  Future<TokenSet?> read() async {
    final raw = await _box.read(_key);
    if (raw == null) {
      return null;
    }
    final json = jsonDecode(raw) as Map<String, Object?>;
    final expires = json['expiresAt'] as String?;
    return TokenSet(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      expiresAt: expires == null ? null : DateTime.parse(expires),
    );
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
}
```

## Failure semantics

The manager loads the store lazily, on the first `current`, `validToken` or
`authorize`; there is no `initialize()` step.

| Operation | If the store throws |
|---|---|
| `read` | The call that triggered the load fails; the next call retries the read. |
| `write` in `setTokens` | `setTokens` fails and the tokens are not published. |
| `write` after a refresh | Not surfaced: the refreshed tokens stay in memory only (the server already rotated the old pair) until the next refresh or `setTokens` writes again. |
| `delete` in `logout` | `logout` fails. |
| `delete` after `InvalidGrant` | Ignored: the grant is dead, so the session ends anyway. |

Tokens are published to `states` only after they are persisted. A storage
failure is never reported as a refresh failure.

## Where to go next

- [Refreshing](refreshing.md) — what runs between `read` and `write`.
- [Testing](testing.md) — a fake store that can be made to fail.
