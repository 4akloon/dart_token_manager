# Getting Started

`token_manager_http` provides `HttpTokenClient`, a `package:http`
`BaseClient` that attaches the tokens of a `TokenManager` to every request
that passes `shouldAuthorize` and replays a request once after the server
rejects them.

## Build the client

```dart
import 'package:http/http.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

HttpTokenClient<TokenSet> buildClient(TokenManager<TokenSet> manager) =>
    HttpTokenClient<TokenSet>(manager: manager, inner: Client());
```

`inner` is the client that really sends: `Client()`, an `IOClient`, a
`RetryClient`, or a `cupertino_http` / `cronet_http` client. For a
`TokenSet` the header is `Authorization: Bearer <accessToken>`. For your own
token type pass `headers`:

```dart
HttpTokenClient<MyTokens>(
  manager: manager,
  inner: Client(),
  headers: (tokens) => {'Authorization': 'Bearer ${tokens.jwt}'},
);
```

Without `headers`, a token type other than `TokenSet` throws an
`ArgumentError`.

## What the client does

For every request that passes `shouldAuthorize` (all of them by default) the
client asks the manager for valid tokens. The manager refreshes them first
when they are about to expire, and concurrent requests share one refresh. A copy of the request is sent with the header, so your
request object never changes. A request that fails `shouldAuthorize` is sent
unchanged without tokens and is never replayed.

If the server rejects the tokens (status 401 by default), the client asks the
manager for a replacement and sends the request **once more**. It never
refreshes by itself and never loops: when the replay is rejected too, that
response is returned.

## Requests without tokens

A login runs before tokens exist. Exclude it with `shouldAuthorize`:

```dart
HttpTokenClient<TokenSet>(
  manager: manager,
  inner: Client(),
  shouldAuthorize: (request) => request.url.path != '/oauth/token',
);
```

## Close it

`close()` closes the inner client, once. It does not dispose the manager,
which may serve other clients: call `manager.dispose()` yourself.

## Run the example

[`example/main.dart`](../example/main.dart) wires the client to a
`MockClient` that answers 401 to a stale token, and shows one refresh and one
replay without a network:

```console
$ dart run example/main.dart
Status 200 after one refresh and replay: {"me":"ada"}
```

## Where to go next

- **Replay**: which requests are replayed and what happens to the rejected
  response.
- **Testing**: test code that uses the client without a network.
