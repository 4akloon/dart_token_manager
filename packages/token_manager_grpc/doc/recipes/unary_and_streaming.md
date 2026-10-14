# Recipe: unary and streaming gRPC calls with one refresh

Attach a bearer token to every gRPC call and refresh once when the server
answers `UNAUTHENTICATED`, for unary and streaming calls alike.

## The code

`GrpcSession` joins a channel, a manager and a `GrpcTokenInterceptor`. Pass its
`interceptor` to every client: `GreeterClient(session.channel, interceptors:
[session.interceptor])` for a generated client. `TokenExchange` is your auth
service client; it must not use the interceptor. `StandInExchange` replaces it.

<!-- include: example/recipes/unary_and_streaming.dart -->
```dart
import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

/// Exchanges a refresh token for new tokens; implement it with a client of
/// your auth service that has no token interceptor.
abstract interface class TokenExchange {
  /// Returns the tokens issued for [refreshToken].
  Future<TokenSet> exchange(String refreshToken);
}

/// Sends the access token as `authorization: Bearer <token>` metadata.
final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  /// Creates the delegate.
  const BearerDelegate();

  @override
  grpc.CallOptions buildCallOptions(TokenSet? tokens) => grpc.CallOptions(
    metadata: {
      if (tokens != null) 'authorization': 'Bearer ${tokens.accessToken}',
    },
  );
}

/// Refreshes through [TokenExchange].
final class ExchangeRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher over [_exchange].
  const ExchangeRefresher(this._exchange);

  final TokenExchange _exchange;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    final refreshToken = current.refreshToken;
    if (refreshToken == null) {
      throw const InvalidGrant();
    }
    try {
      return await _exchange.exchange(refreshToken);
    } on grpc.GrpcError catch (error) {
      if (error.code == grpc.StatusCode.unauthenticated) {
        // The auth service rejected the refresh token for good.
        throw const InvalidGrant();
      }
      rethrow; // anything else, such as UNAVAILABLE, is Transient
    }
  }
}

/// One channel, one manager and the interceptor that joins them.
final class GrpcSession {
  /// Creates a session; [store] defaults to memory.
  factory GrpcSession({
    required grpc.ClientChannel channel,
    required TokenExchange exchange,
    TokenStore<TokenSet>? store,
  }) {
    final manager = TokenManager<TokenSet>.create(
      store: store ?? InMemoryTokenStore<TokenSet>(),
      refresher: ExchangeRefresher(exchange),
      info: const TokenSetInfo(),
    );
    final interceptor = GrpcTokenInterceptor<TokenSet>(
      manager: manager,
      delegate: const BearerDelegate(),
    );
    return GrpcSession._(channel, manager, interceptor);
  }

  const GrpcSession._(this.channel, this.manager, this.interceptor);

  /// The channel every client of the app shares.
  final grpc.ClientChannel channel;

  /// The manager behind [interceptor]; call `setTokens` after sign-in.
  final TokenManager<TokenSet> manager;

  /// Pass it to every generated client, for example
  /// `GreeterClient(channel, interceptors: [session.interceptor])`.
  ///
  /// Unary calls are replayed once after UNAUTHENTICATED. A streaming call is
  /// reopened once, only before its first response and only when its request
  /// stream ended after at most one request.
  final GrpcTokenInterceptor<TokenSet> interceptor;

  /// Shuts the channel down and releases the manager.
  Future<void> close() async {
    await channel.shutdown();
    await manager.dispose();
  }
}

// ---- Stand-in for your auth service, so this file runs without a server.

/// An auth service that issues `access-<n>` on its n-th exchange.
final class StandInExchange implements TokenExchange {
  /// How many exchanges reached the service.
  int calls = 0;

  @override
  Future<TokenSet> exchange(String refreshToken) async {
    calls++;
    return TokenSet(accessToken: 'access-$calls', refreshToken: 'refresh');
  }
}

Future<void> main() async {
  final session = GrpcSession(
    channel: grpc.ClientChannel(
      'localhost',
      port: 50051,
      options: const grpc.ChannelOptions(
        credentials: grpc.ChannelCredentials.insecure(),
      ),
    ),
    exchange: StandInExchange(),
  );
  await session.manager.setTokens(
    const TokenSet(accessToken: 'access-0', refreshToken: 'refresh'),
  );

  // Nothing connects until the first call.
  final client = grpc.Client(
    session.channel,
    interceptors: [session.interceptor],
  );
  stdout.writeln('Client ready: ${client.runtimeType}');

  await session.close();
}
```

Run it with `dart run example/recipes/unary_and_streaming.dart`; it builds the
client and opens no connection. The test
`test/recipes/unary_and_streaming_test.dart` checks every behaviour below with
the fake calls of the package's own tests.

## What you get

- Two unary calls rejected together share one refresh, and each is sent again
  once with the new token.
- A unary call is replayed once; a second `UNAUTHENTICATED` reaches the caller.
- A streaming call is reopened once, only before its first response and only
  when its request stream ended after at most one request, so a response is
  never delivered twice.
- A streaming call that sent more than one request, or whose request stream
  had not ended, is not reopened but still reports its rejected tokens, so the
  next call gets new ones after one refresh.
- A dead refresh token fails the call with `InvalidGrant` and signs the session
  out.
- A transient failure of the exchange, such as `UNAVAILABLE`, fails the call
  with `Transient` and keeps the session.

## Common mistakes

- **Exchanging the refresh token with an intercepted client.** If the auth
  service rejects that call too, it waits for the refresh it belongs to, and
  the original call never completes. Use a client of the auth service without
  the interceptor.
- **Expecting a long client-streaming call to be replayed.** A call that sent
  more than one request, or whose request stream had not ended, is not
  reopened; the error reaches the caller and the rejected tokens are reported
  so the next call gets new ones. A call that already got a response is not
  reopened either, and its error reaches the caller without a report.
- **Mapping every error to `InvalidGrant`.** Only `UNAUTHENTICATED` from the auth
  service means the refresh token is dead; `UNAVAILABLE` is transient.
- **Relying on `PERMISSION_DENIED` to refresh.** The default `shouldRefresh`
  accepts `UNAUTHENTICATED` only; override it in the delegate if your server
  differs.
- **Replaying a call that is not safe to repeat.** A unary call may reach the
  server twice; make it idempotent.

## See also

- [Getting started](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_grpc/doc/getting_started.md)
- [README: client-streaming and bidirectional calls](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_grpc/README.md#client-streaming-and-bidirectional-calls)
