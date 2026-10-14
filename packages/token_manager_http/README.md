# token_manager_http

[![Pub Version](https://img.shields.io/pub/v/token_manager_http.svg)](https://pub.dev/packages/token_manager_http)
![Dart](https://img.shields.io/badge/Dart-%3E%3D3.10-0175C2?logo=dart&logoColor=white)
![Transport](https://img.shields.io/badge/transport-package%3Ahttp-0175C2?logo=dart&logoColor=white)
![Part of](https://img.shields.io/badge/part_of-token__manager-informational)

**The `package:http` adapter for [`token_manager`](https://pub.dev/packages/token_manager)**: `HttpTokenClient`,
a `BaseClient` that wraps your `Client`, attaches the manager's tokens to every request and replays a request
once after the server rejects them. It depends only on `http` and `token_manager`.

## Contents

- [Install](#install)
- [Quick start](#quick-start)
- [What is replayed](#what-is-replayed)
- [Requests without tokens](#requests-without-tokens)
- [Headers and auth failures](#headers-and-auth-failures)
- [Errors](#errors)
- [Closing](#closing)
- [Testing](#testing)
- [Dependency constraints](#dependency-constraints)
- [Reference](#reference)

## Install

```yaml
dependencies:
  http: ^1.5.0
  token_manager: ^0.2.0
  token_manager_http: ^0.1.0
```

## Quick start

```dart
import 'package:http/http.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

Future<String> fetchProfile(TokenManager<TokenSet> manager) async {
  final client = HttpTokenClient<TokenSet>(manager: manager, inner: Client());
  try {
    final response = await client.get(Uri.parse('https://api.example.com/me'));
    return response.body;
  } finally {
    client.close();
  }
}
```

The client never refreshes by itself: it asks the manager for valid tokens (which refreshes them first when
they are about to expire) and reports the tokens a server rejected. Concurrent requests share one refresh.
Every authorized request is sent as a copy, so your request object never gets the token header. A runnable version
without a network is in [example/main.dart](example/main.dart).

**[doc/getting_started.md](doc/getting_started.md)**

## What is replayed

| Request | Replayed after a rejection |
|---|---|
| `Request`: everything `get`, `post`, `put`, `patch`, `delete`, `head` send | once |
| `AbortableRequest` | once, with its abort trigger |
| `StreamedRequest`, `MultipartRequest`, their abortable variants, other subclasses | no |

- **The rejected body is read first.** Before a replay the client reads the 401 to the end, so its connection
  is released. A 401 that is not replayed still reaches you with its body.
- **A request that cannot be replayed** is sent once and its 401 is returned as is. The client reports the
  rejected tokens, so the next request gets new ones.
- **One replay, never a loop.** When the replay is rejected too, that response is returned.

**[doc/replay.md](doc/replay.md)**

## Requests without tokens

A login or sign-up runs before tokens exist. Exclude it with `shouldAuthorize`, and it is sent unchanged
without asking the manager:

```dart
final client = HttpTokenClient<TokenSet>(
  manager: manager,
  inner: Client(),
  shouldAuthorize: (request) => request.url.path != '/oauth/token',
);
```

Without it, a request sent while signed out fails with `NotAuthenticated`.

## Headers and auth failures

| Option | Default |
|---|---|
| `headers` | `Authorization: Bearer <accessToken>` for `TokenSet`; required for any other token type |
| `isAuthFailure` | status **401** |
| `shouldAuthorize` | every request |

```dart
final client = HttpTokenClient<MyTokens>(
  manager: manager,
  inner: Client(),
  headers: (tokens) => {'X-Api-Key': tokens.apiKey},
  isAuthFailure: (response) => {401, 419}.contains(response.statusCode),
);
```

The token header replaces a header with the same name on the request, in any letter case.

## Errors

| Thrown by `send`, `get`, ... | Meaning |
|---|---|
| `NotAuthenticated` | no session; nothing more is sent |
| `InvalidGrant` | the session ended and the manager signed out |
| `Transient` | the refresh may succeed later; the session stays |
| `ClientException` | a network error, or a request after `close()` |

The manager's failures are not wrapped. Listen to `manager.states` to send the user to sign-in on
`Unauthenticated`.

## Closing

`close()` closes the inner client exactly once. It does **not** dispose the manager: the client does not own
it, and several clients may share one manager. Dispose the manager yourself when the session ends.

## Testing

Pass a `MockClient` from `package:http/testing.dart` as `inner` and an `InMemoryTokenStore` to the manager;
nothing touches the network. **[doc/testing.md](doc/testing.md)**

## Dependency constraints

`http ^1.5.0`: 1.5.0 added `AbortableRequest` and `AbortableStreamedRequest`, which the client uses to keep
the abort trigger of a request on the copy it sends.

## Reference

- [doc/getting_started.md](doc/getting_started.md) · [doc/replay.md](doc/replay.md) ·
  [doc/testing.md](doc/testing.md)
- The core: [`token_manager`](https://pub.dev/packages/token_manager); siblings: `token_manager_dio`,
  `token_manager_grpc` and `token_manager_gql`.
- Generate API docs: `cd packages/token_manager_http && dart doc .`
