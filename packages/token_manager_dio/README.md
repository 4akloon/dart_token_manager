# token_manager_dio

[![Pub Version](https://img.shields.io/pub/v/token_manager_dio.svg)](https://pub.dev/packages/token_manager_dio)
![Dart](https://img.shields.io/badge/Dart-%3E%3D3.10-0175C2?logo=dart&logoColor=white)
![Transport](https://img.shields.io/badge/transport-dio-0175C2)
![Part of](https://img.shields.io/badge/part_of-token__manager-informational)

**Dio refresh token interceptor: attach the bearer token, refresh once on 401 and retry the request** — the
[Dio](https://pub.dev/packages/dio) adapter for [`token_manager`](https://pub.dev/packages/token_manager).
One interceptor attaches the access token, recognises an auth failure and replays the request once.
It depends only on the core and `dio`, and never refreshes by itself: the manager owns the refresh.

**Recipes:** [Replace a hand-written refresh interceptor](doc/recipes/replace_refresh_interceptor.md) · [Skip auth for the login and refresh endpoints](doc/recipes/skip_auth_endpoints.md)

## Contents

- [Install](#install)
- [Should I use this?](#should-i-use-this)
- [Quick start](#quick-start)
- [How a request flows](#how-a-request-flows)
- [The delegate](#the-delegate)
- [Errors](#errors)
- [Limitations](#limitations)
- [Migration from 0.1](#migration-from-01)
- [Recipes](#recipes)
- [Reference](#reference)

## Install

```yaml
dependencies:
  token_manager: ^0.2.0
  token_manager_dio: ^0.2.0
```

## Should I use this?

- **Use it when:** the app has an access token and a refresh token, several requests can run at once, and a 401 must trigger exactly one refresh.
- **You do not need it when:** the API uses a long-lived static key, or the app never refreshes tokens.
- **What it replaces:** a hand-written Dio interceptor that refreshes in `onError`. That code tends to refresh once per failed request (N parallel 401s cause N refreshes) and to loop when the refresh itself fails. Here the manager keeps one refresh in flight, a request is replayed at most once, and a failed refresh reaches the caller as a typed error.
- **Which package:**

| You use | Package |
|---|---|
| Any Dart code, or a transport not listed here | [`token_manager`](https://pub.dev/packages/token_manager) |
| `dio` | [`token_manager_dio`](https://pub.dev/packages/token_manager_dio) (this package) |
| `package:http` | [`token_manager_http`](https://pub.dev/packages/token_manager_http) |
| `grpc` | [`token_manager_grpc`](https://pub.dev/packages/token_manager_grpc) |
| GraphQL (`gql_link`) | [`token_manager_gql`](https://pub.dev/packages/token_manager_gql) |

Every adapter needs the core, so install `token_manager` too.

## Quick start

```dart
import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

// Says how the tokens reach the request.
final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const BearerDelegate();

  @override
  void applyTo(RequestOptions options, TokenSet tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
  }
}

void configureClient(Dio dio, TokenManager<TokenSet> manager) {
  dio.interceptors.add(
    DioTokenInterceptor<TokenSet>(
      manager: manager,
      delegate: const BearerDelegate(),
      // The Dio the interceptor is added to: the replay keeps its adapter,
      // its other interceptors and its timeouts.
      dio: dio,
    ),
  );
}
```

A complete runnable program is in [`example/main.dart`](example/main.dart).

## How a request flows

1. **Before sending** — the interceptor asks `TokenManager.validToken()`. Tokens close to expiry are
   refreshed first; concurrent requests share one refresh.
2. **Header** — the delegate's `applyTo` writes the tokens into the request, and the interceptor
   remembers which tokens the request was sent with.
3. **Auth failure** — when `shouldRefresh` accepts the response (status 401 by default), the interceptor
   calls `validToken(rejected: ...)` with the tokens that were rejected.
4. **Replay** — the request is sent again once, on a copy marked as a replay, through the `dio` you
   passed. A marked request is never replayed again, so the interceptor cannot loop.

If the manager returns the very tokens that were rejected, it could not refresh: the original error
reaches the caller and nothing is sent twice.

## The delegate

`RefreshInterceptorDelegate<T>` is the only part you write.

| Member | Purpose |
|---|---|
| `applyTo(options, tokens)` | **Required.** Writes the tokens into the request; `tokens` is never `null`. |
| `shouldRefresh(response)` | Whether a response is an auth failure worth a replay. Defaults to status 401. |

Override `shouldRefresh` for an API that signals expiry differently:

```dart
import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

final class ApiKeyDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const ApiKeyDelegate();

  @override
  void applyTo(RequestOptions options, TokenSet tokens) {
    options.headers['X-Access-Token'] = tokens.accessToken;
  }

  @override
  bool shouldRefresh(Response<Object?>? response) {
    // This API also reports an expired token with a response header.
    return response?.statusCode == 401 ||
        response?.headers.value('X-Token-Expired') == 'true';
  }
}
```

## Errors

The interceptor never swallows a failure to obtain or renew tokens. The `DioException` carries the cause
in `error`:

| `e.error` | Meaning |
|---|---|
| `NotAuthenticated` | There are no tokens: the user is logged out. Nothing was sent. |
| `InvalidGrant` | The refresh token was rejected for good; the manager signed the session out. |
| `Transient` | The refresh failed for a reason that may go away; the session is kept. |

On a refresh failure `e.response` is the 401 that started it. A replay the server rejects again reaches
you as the usual `DioException` of that second response.

## Limitations

- **Streams** — a `Stream` body cannot be sent twice, so the original error is returned and no refresh is
  started.
- **Multipart** — a `FormData` body is cloned. A file part built from a one-shot stream (the deprecated
  `MultipartFile(stream, length)`) is sent empty on the replay; use `MultipartFile.fromFile`,
  `fromBytes` or `fromString`.
- **Same-Dio loop guard** — pass the `Dio` the interceptor is added to. Without `dio:` the replay goes
  through a plain `Dio()` that has none of your adapter, interceptors or timeouts.
- **Methods** — any HTTP method is replayed; make sure a second attempt is safe for non-idempotent calls.

## Migration from 0.1

`RefreshInterceptor` is now `DioTokenInterceptor`, `applyTokensToRequest` is now `applyTo`, and a few
failure paths changed. 0.1 code still compiles, with deprecation warnings.
**[doc/migration.md](doc/migration.md)** lists every change.

## Recipes

Each recipe is one page with complete code that is compiled and tested in this repository.

- [Replace a hand-written refresh interceptor](doc/recipes/replace_refresh_interceptor.md)
- [Skip auth for the login and refresh endpoints](doc/recipes/skip_auth_endpoints.md)

## Reference

- **[doc/getting_started.md](doc/getting_started.md)** — wiring a manager, a delegate and a `Dio`.
- **[doc/migration.md](doc/migration.md)** — upgrading from 0.1.
- [`token_manager`](https://pub.dev/packages/token_manager) — the core: storage, single-flight refresh, errors.
- [CHANGELOG](CHANGELOG.md)

Generate API docs: `cd packages/token_manager_dio && dart doc .`
