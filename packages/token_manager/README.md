## token_manager

[![Pub Version](https://img.shields.io/pub/v/token_manager.svg)](https://pub.dev/packages/token_manager)

`token_manager` is a lightweight core library for token storage, proactive refresh,
and synchronized token state access across your app.

## Features

- Storage abstraction via `TokenStorage<T>`.
- Auto-refresh scheduling via `TokenManagerRefreshDelegate<T>`.
- Refresh synchronization (`waitForFresh`) to avoid concurrent refresh storms.
- Reactive token updates via `tokensStream`.
- Built-in revoke flow via `RevokedTokensException`.

## Installation

```yaml
dependencies:
  token_manager: ^0.1.0
```

## Usage

```dart
import 'package:token_manager/token_manager.dart';

final class AppTokens {
  const AppTokens({
    required this.accessToken,
    required this.expiresAt,
  });

  final String accessToken;
  final DateTime expiresAt;
}

final class MemoryTokenStorage implements TokenStorage<AppTokens> {
  AppTokens? _tokens;

  @override
  AppTokens? getTokens() => _tokens;

  @override
  Future<void> setTokens(AppTokens? tokens) async {
    _tokens = tokens;
  }
}

final class AppRefreshDelegate extends TokenManagerRefreshDelegate<AppTokens> {
  @override
  Future<AppTokens> refresh(AppTokens tokens) async {
    // Replace with real refresh call.
    return AppTokens(
      accessToken: '${tokens.accessToken}_refreshed',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

final class AppTokenInfoDelegate implements TokenInfoDelegate<AppTokens> {
  @override
  DateTime expiresAt(AppTokens tokens) => tokens.expiresAt;
}

Future<void> main() async {
  final manager = TokenManager<AppTokens>(
    storage: MemoryTokenStorage(),
    refreshDelegate: AppRefreshDelegate(),
    infoDelegate: AppTokenInfoDelegate(),
  );

  await manager.initialize();
  await manager.setTokens(
    AppTokens(
      accessToken: 'access_123',
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
    ),
  );
}
```

For a complete runnable example, see `example/main.dart`.