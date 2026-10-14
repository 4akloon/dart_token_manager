# Migrating from 0.1 to 0.2

The old API still works in 0.2, marked `@Deprecated`. It will be removed two
releases after 0.2.

## Mapping

| 0.1 | 0.2 |
|---|---|
| `TokenManager(storage:, refreshDelegate:, infoDelegate:)` | `TokenManager.create(store:, refresher:, info:, skew:)` |
| `TokenStorage<T>`: `getTokens()` / `setTokens(T?)` | `TokenStore<T>`: `read()` / `write(T)` / `delete()` |
| `TokenManagerRefreshDelegate<T>.refresh` | `TokenRefresher<T>.refresh` |
| `refreshThreshold` | `skew` |
| `TokenInfoDelegate<T>` | `TokenInfo<T>` (same method) |
| throw `RevokedTokensException` | throw `InvalidGrant` |
| `tokens` | `await current()` or `states` |
| `tokensStream` | `states` (`Unauthenticated` replaces `null`) |
| `initialize()` | not needed |
| `executeRefresh()` / `waitForFresh` | `validToken()` |
| `setTokens(null)` | `logout()` |

## Before and after

```dart
// 0.1
final manager = TokenManager<MyTokens>(
  storage: MyStorage(),
  refreshDelegate: MyDelegate(),
  infoDelegate: MyInfo(),
);
await manager.initialize();

// 0.2
final manager = TokenManager<MyTokens>.create(
  store: MyStore(),
  refresher: MyRefresher(),
  info: MyInfo(),
);
final tokens = await manager.validToken();
```

## Behaviour changes

- There is no background proactive refresh any more, in the deprecated API
  too. Refresh happens on `validToken`, `authorize` or a rejected token. If
  you relied on `infoDelegate` for refresh before expiry, you lose it until
  you call `validToken` before each use. Proactive refresh is planned for a
  later release.
- `initialize()` no longer rewrites storage; it only loads lazily and is not
  required.
- `refreshDelay` is ignored. There is no retry timer; a transient failure is
  retried by the next call to `validToken`.
- A refresher should throw `InvalidGrant` only when the refresh token was
  rejected for good. Everything else keeps the session.
- `skew` defaults to 30 seconds; the old `refreshThreshold` defaulted to
  3 minutes. Pass `skew: Duration(minutes: 3)` to keep the old margin.
- The minimum SDK is 3.10.
