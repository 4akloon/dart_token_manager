import 'dart:async';

import 'package:token_manager/token_manager.dart';

final class _AppTokens {
  const _AppTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

final class _MemoryTokenStorage implements TokenStorage<_AppTokens> {
  _AppTokens? _tokens;

  @override
  _AppTokens? getTokens() => _tokens;

  @override
  Future<void> setTokens(_AppTokens? tokens) async {
    _tokens = tokens;
  }
}

final class _AppRefreshDelegate
    extends TokenManagerRefreshDelegate<_AppTokens> {
  const _AppRefreshDelegate();

  @override
  Future<_AppTokens> refresh(_AppTokens tokens) async {
    return _AppTokens(
      accessToken: 'new_access_token',
      refreshToken: 'new_refresh_token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

final class _AppTokenInfoDelegate implements TokenInfoDelegate<_AppTokens> {
  const _AppTokenInfoDelegate();

  @override
  DateTime expiresAt(_AppTokens tokens) => tokens.expiresAt;
}

Future<void> main() async {
  final manager = TokenManager<_AppTokens>(
    storage: _MemoryTokenStorage(),
    refreshDelegate: const _AppRefreshDelegate(),
    infoDelegate: const _AppTokenInfoDelegate(),
  );

  await manager.initialize();
  final StreamSubscription<_AppTokens?> tokensSubscription = manager
      .tokensStream
      .listen((_) {});

  await manager.setTokens(
    _AppTokens(
      accessToken: 'access_123',
      refreshToken: 'refresh_123',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    ),
  );

  await tokensSubscription.cancel();
  await manager.dispose();
}
