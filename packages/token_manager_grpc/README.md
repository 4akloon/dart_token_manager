# token_manager_grpc

[![Pub Version](https://img.shields.io/pub/v/token_manager_grpc.svg)](https://pub.dev/packages/token_manager_grpc)

A gRPC client interceptor for [`token_manager`](https://pub.dev/packages/token_manager).
It attaches valid tokens to every call, and when the server rejects them it
refreshes them once (shared by all concurrent calls) and replays the call once.

## Installation

```yaml
dependencies:
  token_manager: ^0.2.0
  token_manager_grpc: ^0.2.0
```

## Usage

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

final manager = TokenManager<TokenSet>.create(
  store: InMemoryTokenStore<TokenSet>(), // or a persistent TokenStore
  refresher: MyRefresher(), // implements TokenRefresher<TokenSet>
  info: const TokenSetInfo(),
);

final client = GreeterClient( // your generated client
  channel,
  interceptors: [
    RefreshInterceptor<TokenSet>(
      manager: manager,
      delegate: const BearerDelegate(),
    ),
  ],
);
```

Override `shouldRefresh` in the delegate when your server reports rejected
tokens with another status than `UNAUTHENTICATED`.

## How calls are replayed

- Without tokens a call fails with `NotAuthenticated` and is not sent.
- A unary call rejected by `shouldRefresh` is replayed once with refreshed
  tokens. A second rejection, or any other error, reaches the caller.
- A streaming call is reopened once only if it was rejected before its first
  response and its request stream ended after at most one request (the shape
  of a server-streaming call). After the first response an error is passed on;
  listen to `manager.states` to resubscribe. Client-streaming and
  bidirectional calls are never reopened: the original error reaches the
  caller, but the rejected tokens are reported to the manager, so the next
  call starts with refreshed tokens.
- If the refresh fails, the call fails with `InvalidGrant` (the session ended)
  or `Transient` (try again later).
- `headers`, `trailers` and `cancel()` follow the call that answered, which may
  be the replay. Pause, resume and cancel reach the gRPC call.

## Migrating from 0.1

The interceptor and delegate keep their names and constructors. Create the
manager with `TokenManager.create`; `initialize()` is no longer needed. See
`CHANGELOG.md` for the behaviour changes.

For a runnable example, see `example/main.dart`.
