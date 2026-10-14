# token_manager_gql

[![Pub Version](https://img.shields.io/pub/v/token_manager_gql.svg)](https://pub.dev/packages/token_manager_gql)
![Dart](https://img.shields.io/badge/Dart-%3E%3D3.10-0175C2?logo=dart&logoColor=white)
![Transport](https://img.shields.io/badge/transport-gql__link-e10098?logo=graphql&logoColor=white)
![Part of](https://img.shields.io/badge/part_of-token__manager-informational)

**The GraphQL adapter for [`token_manager`](https://pub.dev/packages/token_manager)** — a
[`gql_link`](https://pub.dev/packages/gql_link) `Link` that attaches the manager's tokens to every request
and replays a request once after the server rejects them. It works with every client built on `gql_link`
(`graphql`, `graphql_flutter`, `ferry`) and depends only on `gql_link`, `gql_exec` and `token_manager`.

## Contents

- [Install](#install)
- [Quick start](#quick-start)
- [Where the link goes](#where-the-link-goes)
- [How a rejection is recognised](#how-a-rejection-is-recognised)
- [Operations without tokens](#operations-without-tokens)
- [Clients](#clients)
- [Subscriptions](#subscriptions)
- [Errors](#errors)
- [Dependency constraints](#dependency-constraints)
- [Reference](#reference)

## Install

```yaml
dependencies:
  token_manager: ^0.2.0
  token_manager_gql: ^0.1.0
```

## Quick start

```dart
import 'package:gql_dedupe_link/gql_dedupe_link.dart';
import 'package:gql_http_link/gql_http_link.dart';
import 'package:gql_link/gql_link.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

Link buildLink(TokenManager<TokenSet> manager) => Link.from([
  DedupeLink(),
  TokenManagerLink<TokenSet>(
    manager: manager,
    headers: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
  ),
  HttpLink('https://api.example.com/graphql'),
]);
```

The link never refreshes by itself: it asks the manager for valid tokens (which refreshes them first when
they are about to expire) and reports the tokens a server rejected. Concurrent requests share one refresh.
A runnable version without a network is in [example/main.dart](example/main.dart).

**[doc/getting_started.md](doc/getting_started.md)**

## Where the link goes

- **`DedupeLink` → `TokenManagerLink` → `HttpLink`** — after `DedupeLink`, identical requests share one
  send and one replay. Before it, every request carries its own header and deduplication stops working.
- **Never together with `AuthLink`** — graphql_flutter's `AuthLink` would set the same header, and it
  cannot replay.
- **`ErrorLink` goes before `TokenManagerLink`** — never between it and `HttpLink`, or it would handle the
  401 before this link sees it.
- **Subscriptions bypass it** — a WebSocket link ignores `HttpLinkHeaders`. Split subscriptions off before
  this link and authorise the socket with `TokenManagerSocketAuth`:

```dart
import 'package:gql/ast.dart';
import 'package:gql_dedupe_link/gql_dedupe_link.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';

Link splitSubscriptions({
  required Link webSocketLink,
  required Link tokenLink,
  required Link httpLink,
}) => Link.split(
  (request) =>
      request.operation.getOperationType() == OperationType.subscription,
  webSocketLink,
  Link.from([DedupeLink(), tokenLink, httpLink]),
);
```

`DedupeLink` dedupes every operation except mutations by default; pass `shouldDedupe` if subscriptions
also go through it.

## How a rejection is recognised

A server rejects tokens on one of two channels, and `AuthFailureMatcher` recognises both:

| Channel | Default rule |
|---|---|
| An error event, such as `HttpLink`'s `HttpLinkServerException` | a `ServerException` whose `statusCode` is **401** |
| A response whose `errors` carry an auth code (often an HTTP 200) | `errors[].extensions.code` is **`UNAUTHENTICATED`** |

Set other codes with `AuthFailureMatcher(statusCodes: {401, 419}, errorCodes: {'invalid-jwt'})`.

A rejected **response is replayed only when its `data` is null** — a response with data may come from a
mutation that already ran, so it is delivered as is. Only a rejection before the first response is
replayed, and only once. When the replay is rejected too, its error or response reaches the client
unchanged.

`HttpLink` parses the body before it checks the status, so a 401 whose body is not GraphQL JSON (empty,
HTML) arrives as an `HttpLinkParserException`, which has no status code. To replay it, extend the matcher in
your app, which already depends on `gql_http_link`:

```dart
import 'package:gql_http_link/gql_http_link.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

final class AppAuthFailureMatcher extends AuthFailureMatcher {
  const AppAuthFailureMatcher();

  @override
  bool isAuthError(Object error) =>
      (error is HttpLinkParserException && error.response.statusCode == 401) ||
      super.isAuthError(error);
}
```

A response whose HTTP status is not in `statusCodes` (for example 403) is never replayed, even when its
body carries the `UNAUTHENTICATED` code and arrives as a server exception; override `isAuthError` for a
server that answers that way.

**[doc/auth_failures.md](doc/auth_failures.md)**

## Operations without tokens

A login or sign-up runs before tokens exist. Mark it with `SkipAuthorization` and the link forwards it
unchanged, without asking the manager:

```dart
import 'package:gql_exec/gql_exec.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

Request anonymous(Request request) =>
    request.withContextEntry(const SkipAuthorization());
```

Without the marker, a request sent while signed out fails with `NotAuthenticated`.

## Clients

The link depends on no client, so one link serves all of them:

| Client | Where the link goes |
|---|---|
| `graphql` | `GraphQLClient(link: link, cache: ...)` |
| `graphql_flutter` | the same `GraphQLClient`, wrapped in a `ValueNotifier` for `GraphQLProvider` |
| `ferry` | `Client(link: link)` |

**[doc/clients.md](doc/clients.md)**

## Subscriptions

`TokenManagerSocketAuth` supplies tokens to a WebSocket client without depending on one:

```dart
import 'package:graphql/client.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

WebSocketLink buildWebSocketLink(TokenManager<TokenSet> manager) {
  final socketAuth = TokenManagerSocketAuth<TokenSet>(
    manager: manager,
    payload: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
    authCloseCodes: {4401}, // what your server sends when it rejects the tokens
  );
  return WebSocketLink(
    'wss://api.example.com/graphql',
    config: SocketClientConfig(
      initialPayload: socketAuth.initialPayload,
      onConnectionLost: socketAuth.onConnectionLost,
    ),
  );
}
```

`initialPayload` asks for valid tokens on every connect. `onConnectionLost` refreshes the tokens when the
server closes the socket with one of `authCloseCodes` and asks the client to reconnect at once.

What stays the app's job:

- **Tokens that expire on a live socket** — the server checks them when the socket connects. Unless it
  closes the socket with an auth code, nothing happens; reconnect yourself when `manager.states` emits new
  tokens if your server requires it.
- **Logout** — close or dispose the WebSocket link when `manager.states` emits `Unauthenticated`.
- **The reconnect loop after the session ended** — graphql's socket client catches the error
  `initialPayload` throws and retries every `delayBetweenReconnectionAttempts` forever. Dispose the link,
  or set `autoReconnect: false`, when the user is signed out.
- **Bounded reconnects after a refresh** — a server that keeps rejecting fresh tokens would make the
  client loop; bound the retries in the app.
- **Close codes** — WebSockets have no standard auth code; set `authCloseCodes` to what your server sends.
- **Duplicate events** — a resubscription after a reconnect may repeat events; only the app knows whether
  that is safe.

**[doc/subscriptions.md](doc/subscriptions.md)**

## Errors

The manager's failures reach the client as error events, not as `LinkException`s:

| Failure | Meaning |
|---|---|
| `NotAuthenticated` | no session; the request was not sent |
| `InvalidGrant` | the session ended and the manager signed out |
| `Transient` | the refresh may succeed later; the session stays |

Listen to `manager.states` to send the user to sign-in on `Unauthenticated`.

## Dependency constraints

`gql_exec` 1.1.0 is retracted, and `gql_link` 1.1.0 requires `gql_exec ^1.1.0`. This package therefore
accepts `gql_link ^1.0.0` and `gql_exec ^1.0.0`, which resolve to the stable `gql_link` 1.0.0+1 and
`gql_exec` 1.0.0+1 (their API is the same as 1.1.0) and match what `graphql` 5.x and `ferry` require.

## Reference

- [doc/getting_started.md](doc/getting_started.md) · [doc/auth_failures.md](doc/auth_failures.md) ·
  [doc/subscriptions.md](doc/subscriptions.md) · [doc/clients.md](doc/clients.md)
- The core: [`token_manager`](https://pub.dev/packages/token_manager); siblings: `token_manager_dio` and
  `token_manager_grpc`.
- Generate API docs: `cd packages/token_manager_gql && dart doc .`
