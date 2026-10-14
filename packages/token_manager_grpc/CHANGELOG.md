# Changelog

## 0.2.1

Clearer description, topics and recipes.

## 0.2.0

`GrpcTokenInterceptor` replaces `RefreshInterceptor`; a call is replayed at most
once and a response is never delivered twice.

- Renamed `RefreshInterceptor` to `GrpcTokenInterceptor`; the old name is a
  deprecated subclass.
- **Breaking:** requires `token_manager` ^0.2.0. `GrpcTokenInterceptor` sends
  unary calls through `TokenManager.authorize` and streaming calls through
  `TokenManager.authorizeStream`.
- `RefreshInterceptorDelegate.shouldRefresh` is now called: it decides which
  `GrpcError` means the server rejected the tokens (default:
  `UNAUTHENTICATED`).
- **Breaking:** signed out, a call fails with `NotAuthenticated` and is not
  sent. 0.1 sent it without credentials.
- **Breaking:** a failed refresh is the call's error: `InvalidGrant` (the
  session ended and is signed out) or `Transient`. 0.1 swallowed it and
  replayed with the old tokens.
- **Breaking:** a streaming call is reopened only before its first response,
  and only when its request stream ended after at most one request
  (server-streaming calls from generated code). A call whose request stream
  sent more than one request, or had not ended when the call was rejected, is
  never reopened, whatever its method type: the original error reaches the
  caller.
- Such a call (typically client-streaming or bidirectional) rejected with an
  auth failure is not reopened, but the rejected tokens are reported to the
  manager (`validToken(rejected: ...)`), so that a refresh starts for the next
  call. The original error still reaches the caller.
- **Breaking:** for a streaming call `headers` resolves when the first
  response, error or end arrives, or on cancel. If the response stream is never
  listened to or cancelled it never resolves, so a bidirectional call must not
  await `headers` before it listens to the responses.
- **Breaking:** a streaming call is made when its response stream is listened
  to; a stream that is never listened to sends nothing.
- **Breaking:** `headers` and `trailers` follow the call that answered. For a
  streaming call they resolve when the first response, error or end arrives,
  or on cancel; for a unary call once it completes. Without any call (signed
  out, or cancelled before the token arrived) they are empty maps. 0.1
  forwarded the first call's headers.
- **Breaking:** only `Exception`s are handled; an `Error` thrown by the
  delegate or an invoker propagates.
- `buildCallOptions` is never called with `null`.
- Fixed: a rejected call no longer forces a refresh when another call already
  refreshed the tokens; concurrent rejections share one refresh.
- Fixed: a call is replayed at most once.
- Fixed: a streaming call is no longer replayed after it delivered a response,
  so a response is never delivered twice.
- Fixed: a streaming call no longer listens to a single-subscription request
  stream a second time.
- Fixed: `cancel()` reaches the call in flight and, during a refresh, prevents
  the replay; pause and resume reach the call.
- Fixed: errors on the `headers` and `trailers` futures no longer escape as
  uncaught zone errors.
- Removed the internal `AsyncResponseFuture` and `AsyncResponseStream` (never
  exported).

## 0.1.0

Initial gRPC integration package for `token_manager`.

- `RefreshInterceptor<T>` for unary and streaming retry on unauthenticated
  errors.
- `RefreshInterceptorDelegate<T>` extension point for call metadata
  construction.
- Async response wrappers for transparent retry handoff and cancellation.
- Package documentation and runnable example.
