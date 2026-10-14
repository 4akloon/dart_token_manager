# token_manager_grpc

![Dart](https://img.shields.io/badge/Dart-%3E%3D3.10-0175C2?logo=dart&logoColor=white)
[![Pub Version](https://img.shields.io/pub/v/token_manager_grpc.svg)](https://pub.dev/packages/token_manager_grpc)
![Part of](https://img.shields.io/badge/part_of-token__manager-informational)

**gRPC Dart auth token interceptor: attach the bearer token, refresh once on UNAUTHENTICATED and replay the call** — the
`package:grpc` adapter for [token_manager](https://pub.dev/packages/token_manager). It attaches valid tokens
to every call and, when the server rejects them, refreshes once and replays the call once.

> Part of the dart_token_manager workspace. The core owns storage and refresh; this package only
> adapts it to `package:grpc`.

## Contents

- [Install](#install)
- [Should I use this?](#should-i-use-this)
- [Quick start](#quick-start)
- [Unary and streaming calls](#unary-and-streaming-calls)
- [The delegate](#the-delegate)
- [Errors](#errors)
- [Client-streaming and bidirectional calls](#client-streaming-and-bidirectional-calls)
- [Migration from 0.1](#migration-from-01)
- [Recipes](#recipes)
- [Reference](#reference)

## Install

```yaml
dependencies:
  token_manager: ^0.2.0
  token_manager_grpc: ^0.2.0
```

## Should I use this?

- **Use it when:** the app has an access token and a refresh token, several requests can run at once, and a 401 must trigger exactly one refresh.
- **You do not need it when:** the API uses a long-lived static key, or the app never refreshes tokens.
- **What it replaces:** a hand-written gRPC `ClientInterceptor` that refreshes when a call fails. That code tends to refresh once per failed request (N parallel 401s cause N refreshes) and to loop when the refresh itself fails. Here the manager keeps one refresh in flight, a request is replayed at most once, and a failed refresh reaches the caller as a typed error.
- **Which package:**

| You use | Package |
|---|---|
| Any Dart code, or a transport not listed here | [`token_manager`](https://pub.dev/packages/token_manager) |
| `dio` | [`token_manager_dio`](https://pub.dev/packages/token_manager_dio) |
| `package:http` | [`token_manager_http`](https://pub.dev/packages/token_manager_http) |
| `grpc` | [`token_manager_grpc`](https://pub.dev/packages/token_manager_grpc) (this package) |
| GraphQL (`gql_link`) | [`token_manager_gql`](https://pub.dev/packages/token_manager_gql) |

Every adapter needs the core, so install `token_manager` too.

## Quick start

```dart
import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

// Your refresher: exchange the refresh token for a new TokenSet.
final class MyRefresher implements TokenRefresher<TokenSet> {
  const MyRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async => current;
}

// Tells the interceptor how to carry the tokens.
final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const BearerDelegate();

  @override
  grpc.CallOptions buildCallOptions(TokenSet? tokens) => grpc.CallOptions(
    metadata: {
      if (tokens != null) 'authorization': 'Bearer ${tokens.accessToken}',
    },
  );
}

grpc.Client buildClient(grpc.ClientChannel channel) {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(), // or a persistent TokenStore
    refresher: const MyRefresher(),
    info: const TokenSetInfo(),
  );
  // Pass the same list to your generated client:
  // GreeterClient(channel, interceptors: [...]).
  return grpc.Client(
    channel,
    interceptors: [
      GrpcTokenInterceptor<TokenSet>(
        manager: manager,
        delegate: const BearerDelegate(),
      ),
    ],
  );
}
```

**[doc/getting_started.md](doc/getting_started.md)** walks through the same setup step by step.

## Unary and streaming calls

Unary calls go through `TokenManager.authorize`, streaming calls through
`TokenManager.authorizeStream`. A call is replayed **at most once**, and concurrent rejections
share one refresh.

- **Unary** — rejected by `shouldRefresh`: refresh, then replay once. A second rejection or any
  other error reaches the caller.
- **Streaming** — reopened only *before the first response*, so an event is never delivered
  twice. After the first response an error is passed on; resubscribe when `manager.states`
  reports the new session.
- **Pause, resume, cancel** — all reach the gRPC call in flight. `cancel()` during a refresh
  prevents the replay.
- **`headers` and `trailers`** — follow the attempt that answered, which may be the replay. For a
  streaming call they resolve with the first response, error or end, or on cancel.

A streaming call is made when its response stream is listened to; a stream nobody listens to sends
nothing.

## The delegate

`RefreshInterceptorDelegate` has two members:

| Member | Role |
|---|---|
| `buildCallOptions(tokens)` | Returns the `CallOptions` (usually metadata) that carry the tokens; merged into the call's options. |
| `shouldRefresh(error)` | Returns `true` when the `GrpcError` means the server rejected the tokens. Default: `UNAUTHENTICATED`. |

Override `shouldRefresh` when your server uses another status, for example `PERMISSION_DENIED`:

```dart
import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

final class StrictDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const StrictDelegate();

  @override
  grpc.CallOptions buildCallOptions(TokenSet? tokens) => grpc.CallOptions(
    metadata: {
      if (tokens != null) 'authorization': 'Bearer ${tokens.accessToken}',
    },
  );

  @override
  bool shouldRefresh(grpc.GrpcError? error) =>
      error?.code == grpc.StatusCode.unauthenticated ||
      error?.code == grpc.StatusCode.permissionDenied;
}
```

## Errors

- **`NotAuthenticated`** — there are no tokens (logged out); the call is not sent.
- **`InvalidGrant`** — the refresh was rejected for good; the session ended and the manager is
  signed out.
- **`Transient`** — the refresh failed for a reason worth retrying; the session is kept.
- **The original `GrpcError`** — any other failure, or a rejection after the replay.

Only `Exception`s are handled; an `Error` thrown by the delegate or an invoker propagates.

## Client-streaming and bidirectional calls

A call is reopened only when its request stream ended after at most one request, which is the
shape of a server-streaming call. A call that sent more than one request, or whose request stream
had not ended when the server rejected it, is **never reopened**, whatever its method type: the
original error reaches the caller. The rejected tokens are still reported to the manager
(`validToken(rejected: ...)`), so a refresh starts for the next call.

A bidirectional call must listen to its responses before it awaits `headers`: `headers` resolves
with the first response, error or end, so a response stream nobody listens to never resolves it.

## Migration from 0.1

`RefreshInterceptor` is now `GrpcTokenInterceptor` (the old name is a deprecated subclass), refresh
failures reach the call, and signed-out calls fail instead of going out without credentials. See
**[doc/migration.md](doc/migration.md)**.

## Recipes

Each recipe is one page with complete code that is compiled and tested in this repository.

- [Unary and streaming calls with one refresh](doc/recipes/unary_and_streaming.md)

## Reference

- [doc/getting_started.md](doc/getting_started.md) · [doc/migration.md](doc/migration.md) ·
  [CHANGELOG.md](CHANGELOG.md) · [example/main.dart](example/main.dart)
- Core package: [token_manager](https://pub.dev/packages/token_manager)
- Generate API docs: `cd packages/token_manager_grpc && dart doc .`
