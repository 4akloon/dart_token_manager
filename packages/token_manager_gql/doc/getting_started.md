# Getting Started

`token_manager_gql` provides `TokenManagerLink`, a `gql_link` `Link` that
attaches the tokens of a `TokenManager` to GraphQL requests and replays a
request once after the server rejects them.

## Build the link

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

`headers` turns the tokens into request headers. They are merged into the
`HttpLinkHeaders` the request already carries; on a clash the token header
wins.

## What the link does

For every request the link asks the manager for valid tokens. The manager
refreshes them first when they are about to expire, and concurrent requests
share one refresh. The request is then sent with the header.

If the server rejects the tokens, the link asks the manager for a replacement
and sends the request **once more**. It never refreshes by itself and never
loops: when the replay is rejected too, the error or response reaches the client
unchanged.

## Place it in the chain

| Rule | Why |
|---|---|
| `DedupeLink` before `TokenManagerLink` | identical requests share one send and one replay |
| `TokenManagerLink` right before `HttpLink` | it must be able to see the 401 |
| `ErrorLink` before `TokenManagerLink` | an `ErrorLink` after it handles the 401 first |
| Never `AuthLink` as well | both set the header, and `AuthLink` cannot replay |

`TokenManagerLink` cannot end a chain: with no `forward` it throws a
`StateError`. Put a terminating link such as `HttpLink` after it.

## Run the example

[`example/main.dart`](../example/main.dart) wires the link to a fake server
that answers 401 to a stale token, and shows one refresh and one replay without
a network:

```console
$ dart run example/main.dart
Data after one refresh and replay: {me: ada}
```

## Where to go next

- **Auth failures** — how a rejection is recognised and when it is replayed.
- **Subscriptions** — authorise a WebSocket client.
- **Clients** — wire the link into `graphql`, `graphql_flutter` and `ferry`.
