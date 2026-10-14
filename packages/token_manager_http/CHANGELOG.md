# Changelog

## 0.1.0

Initial release of the `package:http` adapter for token_manager.

- `HttpTokenClient<T>`, a `BaseClient` over an inner `Client` that sends
  every request with the headers built from the tokens of a
  `TokenManager<T>` (by default `Authorization: Bearer <accessToken>` for
  `TokenSet`) and never changes the caller's request. A request that
  `shouldAuthorize` declines, such as a login, is sent unchanged without
  tokens.
- A streamed or multipart request is sent once. When the server rejects it
  (`isAuthFailure`, status 401 by default) the response is returned as is and
  the rejected tokens are reported to the manager, so the next request gets
  new ones.
