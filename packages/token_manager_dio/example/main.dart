import 'dart:async';

import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

final class _AppTokens {
  const _AppTokens({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;
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
  Future<_AppTokens> refresh(_AppTokens tokens) async => const _AppTokens(
    accessToken: 'new_access_token',
    refreshToken: 'new_refresh_token',
  );
}

final class _DioAuthDelegate extends RefreshInterceptorDelegate<_AppTokens> {
  const _DioAuthDelegate();

  @override
  void applyTokensToRequest(RequestOptions options, _AppTokens? tokens) {
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
  }
}

Future<void> main() async {
  final manager = TokenManager<_AppTokens>(
    storage: _MemoryTokenStorage(),
    refreshDelegate: const _AppRefreshDelegate(),
  );
  await manager.initialize();
  final StreamSubscription<_AppTokens?> tokensSubscription = manager
      .tokensStream
      .listen((_) {});

  await manager.setTokens(
    const _AppTokens(
      accessToken: 'access_123',
      refreshToken: 'refresh_123',
    ),
  );

  final dio = Dio();
  dio.interceptors.add(
    RefreshInterceptor<_AppTokens>(
      manager: manager,
      delegate: const _DioAuthDelegate(),
    ),
  );

  await tokensSubscription.cancel();
  await manager.dispose();
}
