# Refresh ahead and `refreshIfNeeded`: design

## Goal

Let an app avoid the one slow request that pays for a refresh, without a
background timer. Two additions to the core, both on demand:

- **A. Refresh ahead.** `validToken` returns a still-valid token at once and,
  when the token is close to expiry, starts the refresh in the background.
- **B. `refreshIfNeeded()`.** The app asks for a refresh at a moment it
  chooses (start, resume from background) and awaits it.

This is the "Phase 6" deferred by the redesign
([design](2026-10-14-token-manager-redesign-design.md)). The reasons for
dropping the timer (lifecycle, a busy isolate, refreshing tokens nobody will
use, the old timer bugs) still hold, so this design adds no timer.

Success criteria:

- With `refreshAhead` set, a caller whose token has more than `skew` left never
  waits for a refresh.
- At most one refresh runs at a time, as today; a background refresh and a
  blocking caller share one flight.
- A failed background refresh never signs the user out unless the server said
  `InvalidGrant`, and never produces an unhandled error.
- Default behaviour is unchanged: `refreshAhead` is off unless set.
- Adapters need no code change; they get refresh ahead through `validToken`.

## Non-goals

- A timer or scheduler (`Timer`, `RefreshScheduler`). An app that wants one can
  call `refreshIfNeeded` from its own.
- A proportional window ("refresh at 80 % of the lifetime"). The engine knows
  only `expiresAt` (`TokenInfo` has no issue time), and adding `issuedAt` to
  `TokenInfo` would break every implementer. The window is a fixed `Duration`.

## Design

### Windows

Two thresholds on the time left until `expiresAt`:

| Time left | Today | With `refreshAhead` |
|---|---|---|
| more than `refreshAhead` | return | return |
| between `skew` and `refreshAhead` | return | return, and refresh in the background |
| less than `skew` | refresh and wait | refresh and wait |

`refreshAhead` must be greater than `skew`; `create` throws an `ArgumentError`
otherwise. `null` (the default) turns refresh ahead off.

### A. `TokenManager.create(refreshAhead:)`

`validToken` decides in this order:

1. No tokens: `NotAuthenticated`. No refresher: return the tokens. As today.
2. Rejected token is current, or less than `skew` left: refresh and wait. As
   today, including joining a running flight.
3. Otherwise, if less than `refreshAhead` is left and nothing is in flight and
   this tokens object has not had an ahead attempt yet: start a refresh in the
   background and return the current tokens without waiting.

Rules for the background refresh:

- **Same flight.** It is the session's single flight. A caller that arrives
  during it and needs a refresh (less than `skew` left, or a rejection)
  awaits it like any other.
- **One attempt per tokens object.** The engine remembers the identity of the
  tokens it last tried to refresh ahead. After a failed background attempt it
  does not start another for the same tokens, so a failing server is not
  hammered by every request. When the token reaches `skew`, the blocking path
  of step 2 takes over and retries as today.
- **Failures.** `Transient` (or any other `Exception` wrapped as `Transient`)
  is swallowed: the state returns to `Authenticated`, nothing is thrown, and
  nobody is told. `InvalidGrant` ends the session as it does today: the store
  is cleared and `states` emits `Unauthenticated`. A non-`Exception` `Error`
  is not caught, as everywhere.
- **No unhandled errors.** The background start goes through a dedicated engine
  method that attaches the error handling itself; `validToken` does not return
  or await that future. A bare `unawaited(validToken())` is not used, because
  the future `validToken` returns would fail separately and be unhandled.
- **Epoch.** A background refresh is guarded by the session epoch exactly like
  a blocking one: `setTokens`, `logout` and `InvalidGrant` discard its result,
  so it cannot resurrect a signed-out session.
- **`dispose`.** `dispose` does not bump the epoch today, and its contract is
  that a refresh that finishes later is still persisted. This is deliberate:
  refresh tokens are usually rotated, and dropping the result would lose the
  only valid one. A background refresh that is already running behaves the
  same. After `dispose`, `validToken` does not start new background refreshes.

### B. `refreshIfNeeded`

```dart
/// Refreshes the tokens when less than [within] is left before they expire.
Future<void> refreshIfNeeded({Duration? within});
```

- `within` defaults to `refreshAhead`, or to `skew` when `refreshAhead` is not
  set. A caller can pass a larger value, for example `Duration(minutes: 10)`
  on app resume.
- No tokens, no refresher, or enough time left: completes normally without
  calling the refresher. Unauthenticated is not an error here, because the
  caller is asking "make sure the session is fresh", not "give me a token".
- A refresh is needed: awaits it through the single flight (starting one, or
  joining the running one). `InvalidGrant` and `Transient` are thrown to the
  caller, so the app decides: a start-up code usually ignores `Transient`.
- It never reports a rejected token; that stays in `validToken`.

### Engine and policy

- `RefreshPolicy` gains `isExpiring(tokens, window)`; the existing `skew`
  check becomes `isExpiring(tokens, skew)`. The ahead check uses
  `refreshAhead`.
- `TokenEngine` gains `refreshInBackground` (used by `validToken`, owns the
  error handling and the per-tokens attempt memory) and `refreshIfNeeded`.
  `RefreshAttempt` and `Session` are reused as they are. `TokenEngine` has 15
  members now and the class limit is about 15, so the attempt memory and the
  ahead decision go in a small new class (`AheadRefresh`, one file) that the
  engine holds; the engine's member count must not grow.
- No new public types. `TokenManager` gets one parameter and one method.

## Versioning

The change is additive: no existing call changes meaning. Options:

- **Patch, `token_manager` 0.2.3.** Matches the pre-1.0 rule "a breaking change
  is a minor bump". The adapters' `^0.2.0` constraints still resolve, so no
  adapter is re-released. The only breakage would be for someone who
  `implements TokenManager` (a plain `class`, not `interface`/`final`); the
  repository has none.
- **Minor, `token_manager` 0.3.0.** Safest for such implementers, but `^0.2.0`
  excludes 0.3.0, so all four adapters must be re-released with widened
  constraints.

Recommendation: 0.2.3. The decision is the user's.

## Documentation

- `doc/concepts.md`: replace "Why no background timer" with "Refreshing before
  expiry" (still no timer; what `refreshAhead` and `refreshIfNeeded` do).
- `doc/refreshing.md`: the two windows; the failure rules above.
- `README.md` (core): replace the "no background timer" blockquote; add the
  parameter and method to the API sections.
- `doc/getting_started.md`, `doc/recipes/session_expiry.md` ("Expecting a
  timer"), `doc/migration.md`, and the class doc in `lib/src/token_manager.dart`
  ("never by a background timer"): reword.
- A recipe, "Refresh on app resume", with compiled example code and a test.
- `CHANGELOG.md` entry; `llms.txt` and the recipe index list the new recipe
  (`docs_check` enforces the links).

## Testing

Engine tests use `EngineFixture`, `FakeClock`, `FakeRefresher` (manual
completion) and `FakeTokenStore`.

- A: more than `refreshAhead` left: no refresh. Between the windows: the
  caller gets the old tokens immediately and the refresher is called once.
  Ten concurrent calls in the window: one refresh. A caller with less than
  `skew` left during a background flight joins it.
- A: `Transient` in the background: no throw, state back to `Authenticated`,
  and the next call in the window does not start another attempt; after the
  clock passes `skew` the blocking path retries.
- A: `InvalidGrant` in the background logs out. `logout` or `setTokens` during
  the flight: the result is discarded. After `dispose`: no new background
  refresh. No unhandled error is reported in any failure case (the tests run
  in a zone that fails on uncaught errors).
- B: not needed, no tokens, no refresher: refresher not called, completes. Needed:
  awaits the single flight; throws `InvalidGrant` and `Transient`. `within`
  larger than the default refreshes earlier.
- `create` throws when `refreshAhead <= skew`.
- File and method size limits hold (`size_limits_test`); `dart analyze` clean.

## Risks

- A background refresh runs after `validToken` returned. If the app is
  suspended mid-flight the OS may freeze it; the result is persisted when the
  isolate resumes, and a rotated refresh token is never lost because the
  response is always committed. A refresher that times out reports
  `Transient`.
- One attempt per tokens object means a short outage inside the window costs
  the early refresh, not correctness: the blocking path still refreshes at
  `skew`.
- Apps that never set `refreshAhead` see no change.
