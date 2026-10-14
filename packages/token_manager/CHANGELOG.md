## 0.2.0 - Unreleased

### Added
- `TokenManager.create` with `validToken`, `current`, `states`, `logout`,
  `authorize` and `authorizeStream`.
- `TokenStore<T>`, `TokenRefresher<T>`, `TokenInfo<T>`, `AuthState<T>`,
  `RefreshFailure` (`InvalidGrant`, `Transient`), `NotAuthenticated`, `Clock`,
  `InMemoryTokenStore<T>`, `TokenSet`, `TokenSetInfo` and `TokenManagerRegistry`.

### Changed
- `setTokens(null)` is now the same as `logout()`.
- The minimum SDK is 3.10.
- `rxdart` is no longer a dependency.

### Fixed
- A refresh that failed, or returned a token already close to expiry, could
  deadlock the manager forever.
- A refresh that finished after a login or logout overwrote the new session.
- Tokens were published before they were persisted.
- A storage failure was reported as a refresh failure.

### Deprecated
- The `TokenManager` constructor with `storage`, `refreshDelegate` and
  `infoDelegate`; use `TokenManager.create`.
- `tokens`, `tokensStream`, `initialize()`, `executeRefresh()` and
  `waitForFresh`.
- `TokenStorage`, `TokenManagerRefreshDelegate`, `TokenInfoDelegate` and
  `RevokedTokensException`.

### Behaviour changes
- There is no background proactive refresh any more, in the deprecated API
  too. Refresh happens on `validToken`, `authorize` or a rejected token.
  Legacy users who relied on `infoDelegate` for refresh before expiry lose it
  until they move to `validToken`. Proactive refresh is planned for a later
  release.
- `initialize()` no longer rewrites storage; it is a lazy load and is no
  longer required.
- `refreshDelay` is ignored: there is no retry timer. A transient failure is
  retried by the next call to `validToken`.
- A failed refresh no longer ends in a hang: `InvalidGrant` signs out and any
  other failure keeps the session.

## 0.1.0 - 2026-03-27

### Added
- Initial stable package structure for token lifecycle management.
- `TokenManager<T>` with storage-backed state and refresh coordination.
- `TokenStorage<T>`, `TokenInfoDelegate<T>`, and `TokenManagerRefreshDelegate<T>`.
- Public API documentation and usage examples.
