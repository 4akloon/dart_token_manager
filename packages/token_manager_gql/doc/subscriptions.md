# Subscriptions

A WebSocket link ignores `HttpLinkHeaders`, so `TokenManagerLink` cannot
authorise a subscription. `TokenManagerSocketAuth` supplies the tokens to a
WebSocket client instead, without depending on any client.

## Split subscriptions off

Send subscriptions to the WebSocket link and everything else through the token
link:

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

`DedupeLink` dedupes every operation except mutations by default; pass
`shouldDedupe` if subscriptions also go through it.

## Authorise the socket

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

With `gql_websocket_link`, or a graphql-transport-ws client, pass
`initialPayload` (or the client's `connectionParams`) the same way.

- `initialPayload` asks the manager for valid tokens on every connect and
  builds the connection payload. It throws what `validToken` throws:
  `NotAuthenticated`, `InvalidGrant` or `Transient`.
- `onConnectionLost` refreshes the tokens when the server closes the socket
  with one of `authCloseCodes` and returns `Duration.zero`, so the client
  reconnects at once with the new tokens. For any other close, and when the
  refresh fails, it returns `null` and the client keeps its default delay. It
  never throws an `Exception`: the client calls it from a reconnect loop that
  does not handle errors.

Two auth closes in a row both reconnect at once but refresh only once, because
the second close concerns tokens that were already replaced.

## What stays the app's job

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
  immediate reconnect after it refreshes the tokens. A server that keeps
  rejecting fresh tokens would make the client loop; bound the retries in the
  app.
- **Close codes.** WebSockets have no standard auth code: graphql-ws uses 4401,
  the graphql README uses 4001. Set `authCloseCodes` to what your server sends
  (the default is `{4401}`).
- **Duplicate events.** A resubscription after a reconnect may repeat events;
  only the app knows whether that is safe.
