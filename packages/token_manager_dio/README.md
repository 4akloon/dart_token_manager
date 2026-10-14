# token_manager_dio

[![Pub Version](https://img.shields.io/pub/v/token_manager_dio.svg)](https://pub.dev/packages/token_manager_dio)
![Dart](https://img.shields.io/badge/Dart-%3E%3D3.10-0175C2?logo=dart&logoColor=white)
![Transport](https://img.shields.io/badge/transport-dio-0175C2)
![Part of](https://img.shields.io/badge/part_of-token__manager-informational)

**The [Dio](https://pub.dev/packages/dio) adapter for [`token_manager`](../token_manager)** — one
interceptor that attaches the access token, recognises an auth failure and replays the request once.
It depends only on the core and `dio`, and never refreshes by itself: the manager owns the refresh.

## Contents

- [Install](#install)
- [Quick start](#quick-start)
- [How a request flows](#how-a-request-flows)
- [The delegate](#the-delegate)
- [Errors](#errors)
- [Limitations](#limitations)
- [Migration from 0.1](#migration-from-01)
- [Reference](#reference)

## Install

```yaml
dependencies:
  token_manager: ^0.2.0
  token_manager_dio: ^0.2.0
```

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

## Reference

- **[doc/getting_started.md](doc/getting_started.md)** — wiring a manager, a delegate and a `Dio`.
- **[doc/migration.md](doc/migration.md)** — upgrading from 0.1.
- [`token_manager`](../token_manager) — the core: storage, single-flight refresh, errors.
- [CHANGELOG](CHANGELOG.md)

Generate API docs: `cd packages/token_manager_dio && dart doc .`
