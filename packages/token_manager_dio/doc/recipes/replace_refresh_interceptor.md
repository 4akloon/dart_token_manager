# Recipe: replace a hand-written Dio refresh interceptor

Swap an interceptor that refreshes in `onError` for `DioTokenInterceptor`, so
that any number of parallel 401 responses start exactly one refresh and each
rejected request is replayed once.

## The pattern to remove

An interceptor of this shape has two common faults. N parallel 401s call the
refresh N times, and a request that is rejected again after its retry can be
retried again, which loops. This sketch is not compiled and not part of the
package:

```dart
onError: (error, handler) async {
  if (error.response?.statusCode == 401) {
    final tokens = await refreshTokens(); // runs once per failed request
    error.requestOptions.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    handler.resolve(await dio.fetch(error.requestOptions));
    return;
  }
  handler.next(error);
},
```

## The code

Move the call to your token endpoint into a `TokenRefresher` (see
[sign in and store the tokens](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/recipes/login_and_set_tokens.md)),
then build the client with `ApiClient`. `StandInRefresher` and
`StandInServer` replace your endpoint and your API so the file runs without a
network.

<!-- include: example/recipes/replace_refresh_interceptor.dart -->
```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

/// Writes the access token into the `Authorization` header.
final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  /// Creates the delegate.
  const BearerDelegate();

  @override
  void applyTo(RequestOptions options, TokenSet tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
  }
}

/// A [Dio] for your API that attaches tokens, refreshes once for any number
/// of parallel 401s and replays each rejected request once.
final class ApiClient {
  /// Creates the client; [adapter] replaces the network in tests.
  ApiClient({
    required TokenManager<TokenSet> manager,
    required String baseUrl,
    HttpClientAdapter? adapter,
  }) : dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
    }
    dio.interceptors.add(
      DioTokenInterceptor<TokenSet>(
        manager: manager,
        delegate: const BearerDelegate(),
        // The Dio the interceptor is added to: the replay keeps its adapter,
        // its other interceptors and its timeouts.
        dio: dio,
      ),
    );
  }

  /// The client to use for every authorized call.
  final Dio dio;
}

// ---- Stand-ins for the network and the token endpoint, so this file runs
// ---- without either.

/// A refresher that counts its calls and issues `fresh` tokens.
final class StandInRefresher implements TokenRefresher<TokenSet> {
  /// How many times [refresh] was called.
  int calls = 0;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    calls++;
    return const TokenSet(accessToken: 'fresh', refreshToken: 'refresh-2');
  }
}

/// A server that answers 401 to every access token but `fresh`.
final class StandInServer implements HttpClientAdapter {
  /// The `Authorization` header of every request, in arrival order.
  final List<String?> received = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final authorization = options.headers['Authorization'];
    received.add(authorization is String ? authorization : null);
    final isAccepted = authorization == 'Bearer fresh';
    return ResponseBody.fromString(
      isAccepted ? jsonEncode({'me': 'ada'}) : '',
      isAccepted ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> main() async {
  final refresher = StandInRefresher();
  final server = StandInServer();
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(
      const TokenSet(accessToken: 'stale', refreshToken: 'refresh-1'),
    ),
    refresher: refresher,
  );
  final api = ApiClient(
    manager: manager,
    baseUrl: 'https://api.example.com',
    adapter: server,
  );

  final responses = await Future.wait([
    api.dio.get<Object?>('/me'),
    api.dio.get<Object?>('/me'),
    api.dio.get<Object?>('/me'),
  ]);

  stdout.writeln(
    '${responses.length} responses, ${refresher.calls} refresh, '
    '${server.received.length} requests sent',
  );
  await manager.dispose();
}
```

Run it with `dart run example/recipes/replace_refresh_interceptor.dart`. The
test `test/recipes/replace_refresh_interceptor_test.dart` checks every
behaviour below.

## What you get

- Three parallel requests with a stale token share one refresh, and each
  request is sent twice: once rejected, once replayed with the new token.
- A refresh that returns the very tokens that were rejected sends nothing a
  second time; the original error reaches the caller.
- A dead refresh token reaches the caller as a `DioException` whose `error` is
  `InvalidGrant`; the manager has signed the session out.

## Common mistakes

- **Leaving the old interceptor in place.** Both interceptors then react to a
  401. Delete the old one and the fields that held the tokens.
- **Omitting `dio:`.** Without it a plain `Dio()` sends the replay, without your
  adapter, interceptors and timeouts. Pass the `Dio` the interceptor is added
  to.
- **Refreshing through the same `Dio`.** See
  [skip auth for the login and refresh endpoints](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_dio/doc/recipes/skip_auth_endpoints.md).
- **Replaying a request that is not safe to send twice.** Any HTTP method is
  replayed; make a non-idempotent call safe to repeat.
- **Expecting a stream body to be replayed.** It cannot be sent twice, so its
  original error is returned and no refresh is started.

## See also

- [Getting started](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_dio/doc/getting_started.md)
- [Migrating from 0.1](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_dio/doc/migration.md)
