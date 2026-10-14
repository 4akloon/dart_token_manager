# Getting Started

`token_manager_dio` provides `DioTokenInterceptor` and
`RefreshInterceptorDelegate` — the Dio transport for `package:token_manager`.
The interceptor attaches tokens and replays a rejected request once; the
manager does the refreshing.

```dart
import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const BearerDelegate();

  @override
  void applyTo(RequestOptions options, TokenSet tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
  }
}

Dio buildClient(TokenManager<TokenSet> manager) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
  dio.interceptors.add(
    DioTokenInterceptor<TokenSet>(
      manager: manager,
      delegate: const BearerDelegate(),
      dio: dio,
    ),
  );
  return dio;
}
```

## Build a manager

The interceptor needs a `TokenManager<T>` from the core. It owns storage and
the single-flight refresh:

```dart
import 'package:token_manager/token_manager.dart';

final class TokenEndpoint implements TokenRefresher<TokenSet> {
  const TokenEndpoint();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    // Call your token endpoint here. Throw InvalidGrant when the refresh
    // token was rejected for good, and Transient when a retry may succeed.
    return const TokenSet(accessToken: 'new', refreshToken: 'new_refresh');
  }
}

Future<TokenManager<TokenSet>> buildManager() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: const TokenEndpoint(),
    info: const TokenSetInfo(),
  );
  await manager.setTokens(
    const TokenSet(accessToken: 'access', refreshToken: 'refresh'),
  );
  return manager;
}
```

## Pass the same Dio

Give the interceptor the `Dio` it is added to. The replay is then sent
through that client and keeps its `baseUrl`, adapter, other interceptors and
timeouts. Without `dio:` a plain `Dio()` sends the replay.

## Decide what an auth failure is

`shouldRefresh` defaults to status 401. Override it when the API signals an
expired token another way; `applyTo` is the only required override.

## Handle failures

Failures to obtain or renew tokens arrive as `DioException` with the cause in
`error`:

```dart
import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';

Future<String?> loadProfile(Dio dio) async {
  try {
    final response = await dio.get<String>('/profile');
    return response.data;
  } on DioException catch (e) {
    return switch (e.error) {
      // Logged out: show the login screen.
      NotAuthenticated() => null,
      // The session ended for good.
      InvalidGrant() => null,
      // May succeed later; the session is kept.
      _ => throw e,
    };
  }
}
```

## Where to go next

- Upgrading from 0.1 — `migration.md`.
- Storage, refresh and error types — the `token_manager` package.
