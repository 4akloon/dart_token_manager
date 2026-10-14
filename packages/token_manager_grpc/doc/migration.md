# Migrating from 0.1

0.2 renames the interceptor and tightens its behaviour. The delegate keeps
its name and constructor, so most apps change a type name and the manager
setup.

```dart
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

// 0.1: RefreshInterceptor<TokenSet>(manager: ..., delegate: ...)
GrpcTokenInterceptor<TokenSet> buildInterceptor(
  TokenManager<TokenSet> manager,
  RefreshInterceptorDelegate<TokenSet> delegate,
) => GrpcTokenInterceptor<TokenSet>(manager: manager, delegate: delegate);
```

## Steps

1. Require `token_manager: ^0.2.0` and `token_manager_grpc: ^0.2.0`.
2. Rename `RefreshInterceptor` to `GrpcTokenInterceptor`. The old name is a
   deprecated subclass and still works.
3. Create the manager with `TokenManager.create`; `initialize()` is no longer
   needed. See the
   [core migration guide](../../token_manager/doc/migration.md).
4. Review the behaviour changes below.

## Behaviour changes

- **Signed out** — a call fails with `NotAuthenticated` and is not sent. 0.1
  sent it without credentials.
- **Failed refresh** — it is the call's error: `InvalidGrant` (the session
  ended and is signed out) or `Transient`. 0.1 swallowed it and replayed with
  the old tokens.
- **`shouldRefresh`** — is now called and decides which `GrpcError` means the
  tokens were rejected (default: `UNAUTHENTICATED`).
- **One refresh, one replay** — a rejected call no longer forces a refresh when
  another call already refreshed; concurrent rejections share one. A call is
  replayed at most once.
- **Streaming calls** — reopened only before the first response, and only when
  the request stream ended after at most one request. They are never replayed
  after delivering a response, so a response is never delivered twice. A call
  that is not reopened still reports the rejected tokens to the manager.
- **`headers` and `trailers`** — follow the call that answered; empty maps
  when no call was made. For a streaming call they resolve with the first
  response, error or end, or on cancel, so a bidirectional call must listen
  to its responses before awaiting `headers`. 0.1 forwarded the first call's
  headers.
- **Lazy streaming** — a streaming call is made when its response stream is
  listened to.
- **Cancel, pause, resume** — `cancel()` reaches the call in flight and
  prevents a pending replay; pause and resume reach the call.
- **Errors** — only `Exception`s are handled; an `Error` propagates.
  `buildCallOptions` is never called with `null`.

The internal `AsyncResponseFuture` and `AsyncResponseStream` were never
exported and are gone.
