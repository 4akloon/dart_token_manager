# Changelog

## 0.1.1

- Fix: a 403 whose GraphQL errors carry `extensions.code: UNAUTHENTICATED` is
  now replayed once with refreshed tokens; before, it reached the caller as a
  `ServerException`. A 403 without that code is still not replayed.
- Fix: the manager's failures (`NotAuthenticated`, `InvalidGrant`, `Transient`)
  now arrive as a `LinkException` whose `originalException` is the failure;
  before, they arrived as the raw failure object.
- Docs: how to opt in to other rejections with `AuthFailureMatcher`.
- Docs: the `clients` dartdoc category now lists `TokenManagerLink` and
  `SkipAuthorization`.

## 0.1.0

Initial release of the GraphQL adapter for token_manager.

- `TokenManagerLink<T>`, a `gql_link` `Link` that attaches the tokens of a
  `TokenManager<T>` and replays a request once after the server rejects them,
  on an error event or on a response without data whose errors carry an auth
  code.
- `AuthFailureMatcher`, which recognises a rejection: HTTP 401 and the
  `UNAUTHENTICATED` error code by default.
- `SkipAuthorization`, a request context entry for operations sent without
  tokens, such as a login.
- `TokenManagerSocketAuth<T>`, the `initialPayload` and `onConnectionLost`
  callbacks for GraphQL WebSocket clients.
