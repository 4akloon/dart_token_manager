# Getting Started

`token_manager_grpc` plugs a `TokenManager` into a `package:grpc` client. The
interceptor sends every call with a valid token and, when the server rejects
it, refreshes once and replays the call once.

```yaml
dependencies:
  token_manager: ^0.2.0
  token_manager_grpc: ^0.2.0
```

## 1. Create the manager

The manager lives in `token_manager`; the interceptor only borrows it.

```dart
import 'package:token_manager/token_manager.dart';

final class MyRefresher implements TokenRefresher<TokenSet> {
  const MyRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    // Exchange current.refreshToken with your auth server here.
    return current;
  }
}

TokenManager<TokenSet> buildManager() => TokenManager<TokenSet>.create(
  store: InMemoryTokenStore<TokenSet>(), // or a persistent TokenStore
  refresher: const MyRefresher(),
  info: const TokenSetInfo(),
);
```

## 2. Write a delegate

The delegate decides how tokens travel and which error means "rejected".

```dart
import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const BearerDelegate();

  @override
  grpc.CallOptions buildCallOptions(TokenSet? tokens) => grpc.CallOptions(
    metadata: {
      if (tokens != null) 'authorization': 'Bearer ${tokens.accessToken}',
    },
  );
}
```

`buildCallOptions` is called with tokens on every call; the parameter stays
nullable for compatibility with 0.1. `shouldRefresh` defaults to
`UNAUTHENTICATED`; override it when your server uses another status.

## 3. Add the interceptor

```dart
import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

grpc.Client buildClient(
  grpc.ClientChannel channel,
  TokenManager<TokenSet> manager,
  RefreshInterceptorDelegate<TokenSet> delegate,
) => grpc.Client(
  channel,
  interceptors: [
    GrpcTokenInterceptor<TokenSet>(manager: manager, delegate: delegate),
  ],
);
```

Generated clients take the same `interceptors` list:
`GreeterClient(channel, interceptors: [...])`.

## What happens on a call

- No tokens: the call fails with `NotAuthenticated` and is not sent.
- Rejected tokens: one refresh, shared by every concurrent call, then one
  replay. A second rejection reaches the caller.
- Failed refresh: the call fails with `InvalidGrant` (the session ended and
  the manager signs out) or `Transient` (try again later).
- Streaming: the call is reopened only before its first response and only
  when its request stream ended after at most one request. See
  [Client-streaming and bidirectional calls](../README.md#client-streaming-and-bidirectional-calls).
- `headers`, `trailers`, pause, resume and `cancel()` follow the attempt that
  answered; they reach the gRPC call.

## Where to go next

- [Migrating from 0.1](migration.md)
- [README](../README.md) for the unary and streaming rules in one place
- `example/main.dart` for a runnable client
