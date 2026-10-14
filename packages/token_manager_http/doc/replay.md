# Replay

A request is replayed only when it can be sent a second time with exactly
the same body.

| Request | Sent with tokens | Replayed after a rejection |
|---|---|---|
| `Request` (what `get`, `post`, `put`, `patch`, `delete` and `head` send) | yes, as a copy | once |
| `AbortableRequest` | yes, the abort trigger is kept | once |
| `StreamedRequest`, `AbortableStreamedRequest` | yes, the body is streamed through | no |
| `MultipartRequest`, `AbortableMultipartRequest` | yes | no |
| any other `BaseRequest`, including your own subclass of `Request` | yes | no |

A subclass of `Request` may build its body in `finalize`, so the client does
not copy it.

## The rejected response

- **Replayable request**: the rejected body is read to the end before the
  replay is sent, so its connection is released. If no replay follows (the
  manager has no replacement token, or the replay is rejected too) you get
  the rejected response, with its body.
  If the refresh fails, its `InvalidGrant` or `Transient` is thrown instead
  of the 401.
- **Request that is sent once**: the rejected response is returned untouched.
  The client reports the rejected tokens to the manager without waiting, so
  the next request gets new ones. Resend the request yourself if that is
  safe.

If the body of a rejected response fails to arrive, the call fails with that
`ClientException` and nothing is replayed.

## One refresh for many requests

The client never refreshes. It asks `TokenManager.authorize` for a
replacement of the tokens the server rejected. When ten requests are rejected
at once, the manager runs one refresh and every request is replayed with its
result. When the tokens were already replaced (by another request or by
`setTokens`), the replay uses the new tokens without refreshing.

## Recognising a rejection

`isAuthFailure` decides which responses mean "these tokens were rejected". The
default is status 401. A server that answers 419 or 440 for an expired
session:

```dart
HttpTokenClient<TokenSet>(
  manager: manager,
  inner: Client(),
  isAuthFailure: (response) => {401, 419, 440}.contains(response.statusCode),
);
```

Do not treat 403 as a rejection: it means the tokens are valid but not
allowed, and a refresh does not change that.

## Errors

| Thrown by `send`, `get`, ... | Meaning |
|---|---|
| `NotAuthenticated` | no session; nothing more is sent |
| `InvalidGrant` | the refresh token is dead and the manager signed out |
| `Transient` | the refresh may succeed later; the session stays |
| `ClientException` | a network error, or a request after `close()` |

The manager's failures are not wrapped in a `ClientException`. Listen to
`manager.states` to send the user to sign-in on `Unauthenticated`.
