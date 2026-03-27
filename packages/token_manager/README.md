# Tokens Manager

This module provides functionality for managing authentication tokens. It handles token storage, refresh, and expiration management.

## Key Features

- Token storage and retrieval
- Automatic token refresh before expiration
- Token revocation handling
- Token update stream
- Secure token storage

## Usage

### Creating a Token Manager

```dart
class MyTokensManager extends TokensManager<MyTokens> {
  MyTokensManager({required super.storage});

  @override
  Future<MyTokens> refresh(MyTokens tokens) async {
    // Implement token refresh logic
    final response = await api.refreshTokens(tokens.refreshToken);
    return MyTokens.fromJson(response.data);
  }

  @override
  DateTime? expiresAt(MyTokens tokens) {
    return tokens.expiresAt;
  }
}
```

### Creating a Token Storage

```dart
class SecureTokensStorage implements TokensStorage<MyTokens> {
  final FlutterSecureStorage _storage;

  SecureTokensStorage(this._storage);

  @override
  Future<MyTokens?> getTokens() async {
    final json = await _storage.read(key: 'tokens');
    if (json == null) return null;
    return MyTokens.fromJson(jsonDecode(json));
  }

  @override
  Future<void> setTokens(MyTokens? tokens) async {
    if (tokens == null) {
      await _storage.delete(key: 'tokens');
    } else {
      await _storage.write(
        key: 'tokens',
        value: jsonEncode(tokens.toJson()),
      );
    }
  }
}
```

### Initialization and Usage

```dart
final storage = SecureTokensStorage(FlutterSecureStorage());
final tokensManager = MyTokensManager(storage: storage);

// Initialize
await tokensManager.initialize();

// Subscribe to token changes
tokensManager.tokensStream.listen((tokens) {
  if (tokens != null) {
    // Tokens updated
  } else {
    // Tokens revoked or cleared
  }
});

// Set new tokens
await tokensManager.setTokens(newTokens);

// Clean up resources
await tokensManager.dispose();
```

## Implementation Details

- Tokens are automatically refreshed 3 minutes before expiration
- Concurrent token refresh is supported
- Secure storage through `TokensStorage` abstraction
- Token revocation support via `RevokedTokensException` 