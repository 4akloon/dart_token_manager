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
