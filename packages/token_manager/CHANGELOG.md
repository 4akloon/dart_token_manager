# Changelog

## 0.2.3

Refresh ahead and `refreshIfNeeded`; nothing changes unless you opt in.

- `TokenManager.create(refreshAhead: ...)`: tokens that are valid but expire
  within `refreshAhead` are returned at once and refreshed in the background.
  It must be greater than `skew`, or `create` throws an `ArgumentError`. It is
  off by default. A failed background refresh keeps the session unless the
  server answered `InvalidGrant`, and there is one background attempt per
  tokens object.
- `TokenManager.refreshIfNeeded({Duration? within})`: refreshes at a moment you
  choose, such as start-up or app resume, and waits for it. It completes
  without a session or when enough time is left, and throws `InvalidGrant` or
  `Transient` when the refresh fails.
- Docs: a new recipe, "Refresh the session on app resume", and updated concept
  docs, including a rewritten "Refreshing before expiry" section. There is
  still no background timer.
- The "proactive refresh is planned" note from 0.2.0 is now delivered as an
  opt-in.
- The transport adapters need no change: they get refresh ahead through
  `validToken`.

## 0.2.2

Clearer description, topics and recipes.

## 0.2.1

Internal refactor of the refresh engine; no behaviour change.

- The engine is split into smaller internal classes (refresh policy, serial
  queue, stored-token loader, session, refresh attempt). The public API and
  behaviour are unchanged.
- Docs: `TokenManager` is also listed under the Streams category.

## 0.2.0

Single-flight refresh with typed failures and an observable session state; the
0.1 API stays available, deprecated.

- `TokenManager.create` with `validToken`, `current`, `states`, `logout`,
  `authorize` and `authorizeStream`.
- `TokenStore<T>`, `TokenRefresher<T>`, `TokenInfo<T>`, `AuthState<T>`,
  `RefreshFailure` (`InvalidGrant`, `Transient`), `NotAuthenticated`, `Clock`,
  `InMemoryTokenStore<T>`, `TokenSet` and `TokenSetInfo`.
- **Breaking:** `setTokens(null)` is `logout()` and also discards an in-flight
  refresh.
- **Breaking:** the deprecated `tokensStream` now suppresses consecutive
  identical tokens (`distinct(identical)`) and does not re-emit for
  `Refreshing` or `Authenticated` transitions that carry the same tokens.
- **Breaking:** the minimum SDK is 3.10.
- **Breaking:** `rxdart` is no longer a dependency.
- **Breaking:** `skew` defaults to 30 seconds; the old `refreshThreshold`
  defaulted to 3 minutes. Pass `skew: Duration(minutes: 3)` to keep the old
  margin.
- **Breaking:** there is no background proactive refresh any more, in the
  deprecated API too. Refresh happens on `validToken`, `authorize` or a
  rejected token. Legacy users who relied on `infoDelegate` for refresh before
  expiry lose it until they move to `validToken`. Proactive refresh is planned
  for a later release.
- **Breaking:** `initialize()` no longer rewrites storage; it is a lazy load.
  It is still required when using the synchronous deprecated `tokens` getter
  or the 0.1 dio/grpc adapters, which never trigger a load.
- **Breaking:** the deprecated `executeRefresh()` no longer swallows
  non-`Exception` errors (0.1 used `catch (e)`); a `TypeError` from a delegate
  now propagates.
- **Breaking:** a failed store write after a refresh is not surfaced to the
  caller: the refreshed tokens stay in memory only and the store keeps the old
  pair until the next successful write.
- **Breaking:** `refreshDelay` is ignored: there is no retry timer. A
  transient failure is retried by the next call to `validToken`.
- A failed refresh no longer ends in a hang: `InvalidGrant` signs out and any
  other failure keeps the session.
- Fixed: a refresh that failed, or returned a token already close to expiry,
  could deadlock the manager forever.
- Fixed: a refresh that finished after a login or logout overwrote the new
  session.
- Fixed: tokens were published before they were persisted.
- Fixed: a storage failure was reported as a refresh failure.
- Deprecated: the `TokenManager` constructor with `storage`, `refreshDelegate`
  and `infoDelegate`; use `TokenManager.create`.
- Deprecated: `tokens`, `tokensStream`, `initialize()`, `executeRefresh()` and
  `waitForFresh`.
- Deprecated: `TokenStorage`, `TokenManagerRefreshDelegate`,
  `TokenInfoDelegate` and `RevokedTokensException`.

## 0.1.0

Initial stable package structure for token lifecycle management.

- `TokenManager<T>` with storage-backed state and refresh coordination.
- `TokenStorage<T>`, `TokenInfoDelegate<T>`, and
  `TokenManagerRefreshDelegate<T>`.
- Public API documentation and usage examples.
