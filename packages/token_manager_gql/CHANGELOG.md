## 0.1.0 - Unreleased

### Added

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
