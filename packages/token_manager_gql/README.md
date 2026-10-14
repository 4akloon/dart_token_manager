# token_manager_gql

[![Pub Version](https://img.shields.io/pub/v/token_manager_gql.svg)](https://pub.dev/packages/token_manager_gql)

A [`gql_link`](https://pub.dev/packages/gql_link) `Link` that attaches the
tokens of a [`token_manager`](https://pub.dev/packages/token_manager)
`TokenManager` to GraphQL requests and replays a request once after the server
rejects them. It works with every client built on `gql_link`, such as
`graphql`, `graphql_flutter` and `ferry`, and depends only on `gql_link`,
`gql_exec` and `token_manager`.

## Installation

```yaml
dependencies:
  token_manager: ^0.1.0
  token_manager_gql: ^0.1.0
```

## Usage

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

Pass the link to your client: `GraphQLClient(link: link, cache: ...)` for
`graphql` and `graphql_flutter`, `Client(link: link)` for `ferry`.

A runnable version without a network is in [example/main.dart](example/main.dart).

### Where the link goes

- **`DedupeLink` → `TokenManagerLink` → `HttpLink`.** After `DedupeLink`,
  identical requests share one send and one replay. Before it, every request
  carries its own header and deduplication stops working.
- **Never together with graphql's `AuthLink`.** Both would set the header,
  and `AuthLink` cannot replay.
- **`ErrorLink` goes before `TokenManagerLink`**, never between it and
  `HttpLink`, or it would handle the 401 before this link sees it.
- **Subscriptions bypass it.** A WebSocket link ignores `HttpLinkHeaders`, so
  split subscriptions off before this link and authorise the socket with
  `TokenManagerSocketAuth` (see below):

  ```dart
  Link.split(
    (request) =>
        request.operation.getOperationType() == OperationType.subscription,
    webSocketLink,
    Link.from([DedupeLink(), tokenLink, httpLink]),
  );
  ```

  `DedupeLink` dedupes every operation except mutations by default; pass
  `shouldDedupe` if subscriptions also go through it.

## How a rejection is recognised

A server rejects tokens on one of two channels, and `AuthFailureMatcher`
recognises both:

| Channel | Default rule |
|---|---|
| An error event, such as `HttpLink`'s `HttpLinkServerException` | a `ServerException` whose `statusCode` is 401 |
| A response whose `errors` carry an auth code (often an HTTP 200) | `errors[].extensions.code` is `UNAUTHENTICATED` |

Set other codes with
`AuthFailureMatcher(statusCodes: {401, 419}, errorCodes: {'invalid-jwt'})`.

A rejected **response is replayed only when its `data` is null**. A response
with data may come from a mutation that already ran, so it is delivered as is.
Only a rejection before the first response is replayed, and only once. When
the replay is rejected too, its error or response reaches the client
unchanged.

A response whose HTTP status is not in `statusCodes` (for example 403) is never
replayed, even when its body carries the `UNAUTHENTICATED` code and arrives as
a server exception. An app whose server answers that way subclasses
`AuthFailureMatcher` and overrides `isAuthError`.

`HttpLink` parses the body before it checks the status, so a 401 whose body is
not GraphQL JSON (empty, HTML) arrives as an `HttpLinkParserException`, which
has no status code. To replay it, extend the matcher in your app, which
already depends on `gql_http_link`:

```dart
final class AppAuthFailureMatcher extends AuthFailureMatcher {
  const AppAuthFailureMatcher();

  @override
  bool isAuthError(Object error) =>
      (error is HttpLinkParserException && error.response.statusCode == 401) ||
      super.isAuthError(error);
}
```

## Operations without tokens

A login or sign-up runs before tokens exist. Mark it with `SkipAuthorization`
and the link forwards it unchanged, without asking the manager:

```dart
// gql_link
final login = request.withContextEntry(const SkipAuthorization());

// graphql
MutationOptions(
  document: loginMutation,
  context: Context().withEntry(const SkipAuthorization()),
);
```

Without the marker, a request sent while signed out fails with
`NotAuthenticated`.

## Errors

The link never refreshes by itself: it asks the manager for valid tokens and
reports the tokens a server rejected. The manager's failures reach the client
as error events: `NotAuthenticated` (no session), `InvalidGrant` (the session
ended and the manager signed out) and `Transient` (the refresh may succeed
later; the session stays). They are not `LinkException`s. Listen to
`manager.states` to send the user to sign-in on `Unauthenticated`.

## Subscriptions

`TokenManagerSocketAuth` supplies tokens to a WebSocket client without
depending on one:

```dart
final socketAuth = TokenManagerSocketAuth<TokenSet>(
  manager: manager,
  payload: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
  authCloseCodes: {4401}, // what your server sends when it rejects the tokens
);

// graphql / graphql_flutter
final webSocketLink = WebSocketLink(
  'wss://api.example.com/graphql',
  config: SocketClientConfig(
    initialPayload: socketAuth.initialPayload,
    onConnectionLost: socketAuth.onConnectionLost,
  ),
);
```

`initialPayload` asks for valid tokens on every connect. `onConnectionLost`
refreshes the tokens when the server closes the socket with one of
`authCloseCodes` and asks the client to reconnect at once. With
`gql_websocket_link`, pass `initialPayload` (or the graphql-transport-ws
client's `connectionParams`) the same way.

What stays the app's job:

- **Tokens that expire on a live socket.** The server checks them when the
  socket connects. Unless it closes the socket with an auth code, nothing
  happens; reconnect yourself when `manager.states` emits new tokens if your
  server requires it.
- **Logout.** Close or dispose the WebSocket link when `manager.states` emits
  `Unauthenticated`.
- **The reconnect loop after the session ended.** graphql's socket client
  catches the error `initialPayload` throws (`InvalidGrant`, then
  `NotAuthenticated`) and tries again every `delayBetweenReconnectionAttempts`
  (5 seconds by default), forever. Dispose the link, or set
  `autoReconnect: false`, when the user is signed out.
- **Bounded reconnects after a refresh.** `onConnectionLost` asks for an
  immediate reconnect after it refreshes the tokens. Bound the reconnect
  retries in the app, or a server that keeps rejecting fresh tokens would make
  the client loop.
- **Close codes.** WebSockets have no standard auth code: graphql-ws uses 4401,
  the graphql README uses 4001. Set `authCloseCodes` to what your server sends.
- **Duplicate events.** A resubscription after a reconnect may repeat events;
  only the app knows whether that is safe.

## Dependency constraints

`gql_exec` 1.1.0 is retracted, and `gql_link` 1.1.0 requires `gql_exec ^1.1.0`.
This package therefore accepts `gql_link ^1.0.0` and `gql_exec ^1.0.0`, which
resolve to the stable `gql_link` 1.0.0+1 and `gql_exec` 1.0.0+1 (their API is
the same as 1.1.0) and match what `graphql` 5.x and `ferry` require.
