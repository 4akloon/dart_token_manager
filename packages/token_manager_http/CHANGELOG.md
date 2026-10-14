# Changelog

## 0.1.2

Clearer description, topics and recipes.

## 0.1.1

Internal refactor and documentation fixes; no behaviour change.

- The client defaults moved out of `HttpTokenClient` into their own internal
  class. The public API and behaviour are unchanged.
- Docs: exact wording on which requests get tokens (`shouldAuthorize`) and
  which are replayed, including requests that cannot be replayed.
- Docs: the rejected response body is buffered without a size cap, and
  its headers are copied.

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
- A `Request` or `AbortableRequest` that the server rejects is sent once more
  with the tokens `TokenManager.authorize` provides; concurrent rejections
  share one refresh. The rejected body is read first so its connection is
  released, and a rejection that is not replayed is returned with its body.
- `close()` closes the inner client once and leaves the manager open; a
  request after `close()` fails with a `ClientException`.
