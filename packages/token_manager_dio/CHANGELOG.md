## 0.2.0 - Unreleased

### Changed
- `RefreshInterceptor<T>` is built on the new `token_manager` core: the header
  comes from `TokenManager.validToken()` and a rejected request is replayed
  after `validToken(rejected: ...)`. The constructor and
  `RefreshInterceptorDelegate<T>` (`applyTokensToRequest`, `shouldRefresh`) are
  source compatible with 0.1.
- Requires `token_manager` 0.2.0 and no longer uses its deprecated API
  (`tokens`, `waitForFresh`, `executeRefresh`, `initialize`).
- `applyTokensToRequest` now always receives non-null tokens.
- The replay is sent with `Dio.fetch` on a copy of the request: the `Dio` given
  as `dio` keeps its `baseUrl` (0.1 overwrote it), the response type of the
  request is kept, and a `FormData` body is cloned.
- The request is no longer tagged with `extra['_auth_tokens']`; the interceptor
  uses `extra['token_manager_dio.tokens']`.

### Behaviour changes
- A request made while logged out fails with a `DioException` whose `error` is
  `NotAuthenticated` and is not sent. 0.1 sent it without credentials.
- A failure to renew tokens is no longer swallowed: the `DioException.error` is
  `InvalidGrant` (the session ended) or `Transient` (the session is kept), with
  the original 401 as `response`. 0.1 swallowed refresh errors and replayed
  with stale or missing tokens.
- A replay is marked with `extra['token_manager_dio.replayed']` and is replayed
  at most once. This ends the endless loop of 0.1 when the `Dio` that owns the
  interceptor was passed as `dio` and the server kept answering 401.
- If the manager returns the tokens that were rejected, the original error is
  returned instead of sending the same request again.
- A request with a `Stream` body is not replayed and starts no refresh; the
  original error is returned.
- Refresh now follows the core: tokens close to expiry (`skew`, 30 seconds by
  default) are refreshed before the request, and there is no `waitForFresh`
  step because `validToken` joins a refresh in flight.

## 0.1.0 - 2026-03-27

### Added
- Initial Dio integration package for `token_manager`.
- `RefreshInterceptor<T>` for token injection and refresh-aware retry.
- `RefreshInterceptorDelegate<T>` extension point for auth mapping logic.
- Package documentation and runnable example.
