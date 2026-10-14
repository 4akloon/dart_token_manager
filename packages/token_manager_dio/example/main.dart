import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

final class _BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const _BearerDelegate();

  @override
  void applyTokensToRequest(RequestOptions options, TokenSet? tokens) {
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
  }
}

final class _ExampleRefresher implements TokenRefresher<TokenSet> {
  const _ExampleRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    // Call your token endpoint here. Throw InvalidGrant when the refresh
    // token was rejected for good, and Transient when a retry may succeed.
    return const TokenSet(
      accessToken: 'new_access_token',
      refreshToken: 'new_refresh_token',
    );
  }
}

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: const _ExampleRefresher(),
    info: const TokenSetInfo(),
  );
  await manager.setTokens(
    const TokenSet(accessToken: 'access_123', refreshToken: 'refresh_123'),
  );

  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
  // Pass the same Dio, so the replay keeps its adapter and interceptors.
  dio.interceptors.add(
    DioTokenInterceptor<TokenSet>(
      manager: manager,
      delegate: const _BearerDelegate(),
      dio: dio,
    ),
  );

  await manager.dispose();
}
