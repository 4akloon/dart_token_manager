# Migration from 0.1

0.2 builds the interceptor on the new `token_manager` core. Existing 0.1
code compiles and works, with deprecation warnings; the behaviour changes
below are the only things that can surprise you.

```dart
import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

// 0.1
final class OldDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const OldDelegate();

  @override
  // ignore: deprecated_member_use, shown for comparison.
  void applyTokensToRequest(RequestOptions options, TokenSet? tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens?.accessToken}';
  }
}

// 0.2
final class NewDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const NewDelegate();

  @override
  void applyTo(RequestOptions options, TokenSet tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
  }
}
```

## Renames

| 0.1 | 0.2 |
|---|---|
| `RefreshInterceptor<T>` | `DioTokenInterceptor<T>` (the old name is a deprecated subclass) |
| `applyTokensToRequest(options, tokens)` | `applyTo(options, tokens)`; `tokens` is non-null |
| `extra['_auth_tokens']` | `extra['token_manager_dio.tokens']` |

Both delegate methods are concrete. A delegate that overrides only
`applyTokensToRequest` keeps working; one that overrides neither fails with a
`StateError`.

## Behaviour changes

- **Logged out** — a request fails with a `DioException` whose `error` is
  `NotAuthenticated` and is not sent. 0.1 sent it without credentials.
- **Refresh failures** — no longer swallowed: `error` is `InvalidGrant` (the
  session ended) or `Transient` (the session is kept), with the original 401
  as `response`.
- **Replay at most once** — a replay is marked with
  `extra['token_manager_dio.replayed']`. This ends the endless loop of 0.1
  when the `Dio` owning the interceptor was passed as `dio` and the server
  kept answering 401.
- **Same tokens** — if the manager returns the tokens that were rejected, the
  original error is returned instead of sending the same request again.
- **Stream bodies** — not replayed and no refresh is started.
- **Refresh timing** — tokens close to expiry (`skew`, 30 seconds by default)
  are refreshed before the request; a refresh in flight is joined.
- **Replay request** — sent with `Dio.fetch` on a copy: the `baseUrl` of `dio`
  is kept (0.1 overwrote it), the response type is kept, a `FormData` body is
  cloned.

## Requirements

- `token_manager` 0.2.0, whose deprecated API (`tokens`, `waitForFresh`,
  `executeRefresh`, `initialize`) the interceptor no longer uses.
- `dio` 5.3.1 or newer, for `FormData.clone`.

## Conventions

- Override `applyTo` in new delegates; drop `applyTokensToRequest`.
- Pass `dio:` so the replay goes through your client.
- Handle `NotAuthenticated`, `InvalidGrant` and `Transient` in
  `DioException.error`.
