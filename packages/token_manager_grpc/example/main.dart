import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

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
  Future<_AppTokens> refresh(_AppTokens tokens) async {
    return const _AppTokens(
      accessToken: 'new_access_token',
      refreshToken: 'new_refresh_token',
    );
  }
}

final class _GrpcAuthDelegate extends RefreshInterceptorDelegate<_AppTokens> {
  const _GrpcAuthDelegate();

  @override
  grpc.CallOptions buildCallOptions(_AppTokens? tokens) {
    final metadata = <String, String>{};
    if (tokens != null) {
      metadata['authorization'] = 'Bearer ${tokens.accessToken}';
    }
    return grpc.CallOptions(metadata: metadata);
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

  final grpc.ClientInterceptor interceptor = RefreshInterceptor<_AppTokens>(
    manager: manager,
    delegate: const _GrpcAuthDelegate(),
  );
  _configureClient(<grpc.ClientInterceptor>[interceptor]);

  await tokensSubscription.cancel();
  await manager.dispose();
}

void _configureClient(List<grpc.ClientInterceptor> interceptors) {
  if (interceptors.isEmpty) {
    throw ArgumentError.value(
      interceptors,
      'interceptors',
      'At least one interceptor is required.',
    );
  }
}
