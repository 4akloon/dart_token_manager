## token_manager_dio

[![Pub Version](https://img.shields.io/pub/v/token_manager_dio.svg)](https://pub.dev/packages/token_manager_dio)

`token_manager_dio` provides a Dio interceptor on top of `token_manager`:

- attaches a valid access token to every request (the manager refreshes it
  first when it is about to expire);
- when the server rejects a request, asks the manager for a replacement and
  sends the request again once;
- shares one refresh between concurrent requests;
- never loops: a replayed request is marked and is not replayed again.

## Installation

```yaml
dependencies:
  token_manager: ^0.2.0
  token_manager_dio: ^0.2.0
```

## Usage

```dart
import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const BearerDelegate();

  @override
  void applyTokensToRequest(RequestOptions options, TokenSet? tokens) {
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
  }
}

void configureClient(Dio dio, TokenManager<TokenSet> manager) {
  dio.interceptors.add(
    RefreshInterceptor<TokenSet>(
      manager: manager,
      delegate: const BearerDelegate(),
      // The Dio the interceptor is added to: the replay keeps its adapter,
      // its other interceptors and its timeouts.
      dio: dio,
    ),
  );
}
```

For a complete runnable example, see `example/main.dart`.

## What a failure looks like

The interceptor never swallows a failure to obtain or renew tokens. The
`DioException` carries the cause in `error`:

| `e.error` | Meaning |
|---|---|
| `NotAuthenticated` | There are no tokens: the user is logged out. Nothing was sent. |
| `InvalidGrant` | The refresh token was rejected for good; the manager signed the session out. |
| `Transient` | The refresh failed for a reason that may go away; the session is kept. |

On a refresh failure `e.response` is the 401 that started it. A replay that
the server rejects again reaches you as the usual `DioException` of that
second response.

## Replay rules

- Only the failures `RefreshInterceptorDelegate.shouldRefresh` accepts (status
  401 by default) trigger a replay, for any HTTP method.
- A replay carries `extra['token_manager_dio.replayed'] == true`; the tokens a
  request was sent with are in `extra['token_manager_dio.tokens']`.
- A `FormData` body is cloned. A `Stream` body cannot be sent twice, so the
  original error is returned and no refresh is started. A multipart file part
  built from a one-shot stream (the deprecated `MultipartFile(stream, length)`
  constructor) is sent empty on the replay, because the stream was already
  read; use `MultipartFile.fromFile`, `fromBytes` or `fromString`.
- If the manager returns the same tokens that were rejected (it cannot
  refresh), the original error is returned.
- Without the `dio` argument the replay goes through a plain `Dio()`; pass the
  `Dio` you added the interceptor to unless you want that.
