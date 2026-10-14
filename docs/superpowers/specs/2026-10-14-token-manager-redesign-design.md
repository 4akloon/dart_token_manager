# token_manager redesign: design and roadmap

Date: 2026-10-14. Status: awaiting review.

## 1. Goal and constraints

Redesign the `dart_token_manager` workspace so that its structure and architecture
follow patterns proven in other ecosystems, fix the correctness bugs found in
review, adopt the code style and rules of the sibling project `typed_openapi`,
and give existing users a migration path.

Agreed constraints:

- Existing users exist. Old API stays as `@Deprecated` facade for two releases
  after the new API ships (default; open for change, see section 9).
- Several token providers or token types per application.
- Integrations: dio, `package:http`, gRPC, and the `gql_link` ecosystem
  (`graphql_flutter`, `ferry`).
- Storage implementations: secure storage and shared_preferences.
- Streams must never be consumed with `await for`. Pause, resume and cancel
  must reach the source so the stream lifecycle is preserved.
- The token type stays generic (`T`), as in the current API.

## 2. Findings from the code review

Based on reading the code only. Nothing was built or run.

Critical bugs in `packages/token_manager/lib/src/token_manager.dart`:

- `executeRefresh` deadlocks: after a failed refresh, or after a refresh that
  returns a short-lived token, `_setTimer` computes a zero or negative delay and
  awaits `executeRefresh` against the manager's own pending completer.
- `initialize()` does not arm the refresh timer for tokens loaded from storage.
- A concurrent `setTokens` (login or logout) is overwritten by an in-flight refresh.
- `TokenStore.setTokens` emits to the stream before persisting, and concurrent
  calls are not serialised.
- `dispose()` does not stop an in-flight refresh, which can re-arm a timer afterwards.
- A blanket `catch (e)` swallows storage failures as refresh failures.

Adapters:

- dio: the retry goes through `dio ?? Dio()`, skipping the user's interceptors,
  mutates the shared `baseUrl`, and loops forever if the same `Dio` is passed and
  the server keeps answering 401.
- gRPC: no `requestTokens == tokens` check, so every late 401 triggers another
  refresh; streaming retry reuses a single-subscription stream; cancel is not
  forwarded; `shouldRefresh` in the delegate is never called;
  `AsyncResponseStream` ignores pause and resume; errors on the `headers` and
  `trailers` futures can surface as uncaught zone errors.
- Both adapter packages exported `RefreshInterceptor` and `RefreshInterceptorDelegate`,
  which clashed when used together (since renamed to `DioTokenInterceptor` and `GrpcTokenInterceptor`).

Packaging and process:

- `resolution: workspace` appears only in tracked `pubspec_overrides.yaml`, not
  in `pubspec.yaml`; the workspace is probably broken.
- No tests, no CI. Packages are at version 0.1.0.

## 3. Approach

Layered redesign: a dependency-free core that follows the shared shape of Go
`oauth2` `TokenSource`, Ktor bearer auth, Alamofire `AuthenticationInterceptor`,
Spring `OAuth2AuthorizedClientManager`, and MSAL; thin transport adapters;
storage in separate packages.

Principles taken from the research:

1. Minimal core interface; everything else decorates it.
2. Single-flight refresh through one shared in-flight future plus a
   compare-and-skip check: a request rejected with token X must not trigger a
   refresh if the current token is no longer X.
3. Storage is an injected seam; the core does no platform I/O.
4. Core and HTTP adapters are separate. An adapter attaches the header,
   recognises an auth failure, and replays once. It never refreshes by itself.
5. Proactive and reactive refresh share one code path.
6. Loop protection is mandatory and lives in one place.
7. Failures are typed: an invalid refresh token (log out) is distinct from a
   transient error (keep the session).
8. State changes are observable as a stream.

Rejected alternatives: (A) fix bugs and rename only, which keeps the structure
that was the reason for the redesign; (C) one generic Alamofire-style
interceptor owning everything, which fits streams and multiple providers poorly.

## 4. Packages and dependencies

```
token_manager                       core, pure Dart, no dependencies (rxdart removed)
|- token_manager_dio                + dio
|- token_manager_http               + http
|- token_manager_grpc               + grpc
|- token_manager_gql                + gql_link  (graphql_flutter, ferry)
|- token_manager_secure_storage     + flutter_secure_storage
`- token_manager_shared_preferences + shared_preferences
```

- Adapters depend only on the core and their transport. Public names are unique:
  `DioTokenInterceptor`, `HttpTokenClient`, `GrpcTokenInterceptor`, `TokenManagerLink`.
- Storage packages depend only on the core and their plugin, so core users do
  not pull Flutter dependencies.
- `token_manager`, `token_manager_dio` and `token_manager_grpc` keep their
  names. Their old API becomes a deprecated facade over the new core.

## 5. Core API

```dart
abstract interface class TokenStore<T> {
  Future<T?> read();
  Future<void> write(T tokens);
  Future<void> delete();
}

abstract interface class TokenRefresher<T> {
  /// Throws [RefreshFailure]: InvalidGrant (terminal) or Transient.
  Future<T> refresh(T current);
}

abstract interface class TokenInfo<T> {
  DateTime? expiresAt(T tokens); // null: does not expire
}

sealed class AuthState<T> {} // Unauthenticated | Authenticated(T) | Refreshing(T)

class TokenManager<T> {
  TokenManager.create({
    required TokenStore<T> store,
    TokenRefresher<T>? refresher, // null: tokens are never refreshed
    TokenInfo<T>? info, // null: tokens never expire
    Duration skew = const Duration(seconds: 30),
    Clock clock = const Clock(),
  });

  Stream<AuthState<T>> get states; // replays the last value
  Future<T?> current(); // no refresh
  Future<T> validToken({T? rejected});
  Future<void> setTokens(T? tokens); // null logs out; prefer logout()
  Future<void> logout();
  Future<void> dispose();

  Future<R> authorize<R>(
    Future<R> Function(T tokens) send, {
    required bool Function(Object error) isAuthFailure,
  });

  Stream<R> authorizeStream<R>(
    Stream<R> Function(T tokens) open, {
    required bool Function(Object error) isAuthFailure,
  });
}
```

`TokenManager<T>` keeps its name and is evolved in place (decided during
planning, because the old and new classes cannot share a name in one barrel).
The new members sit next to the old ones, which become `@Deprecated`. The
unnamed constructor keeps the old `storage`, `refreshDelegate` and
`infoDelegate` parameters and is deprecated; `TokenManager.create` is the new
entry point. All logic lives in an internal `TokenEngine<T>` that
`TokenManager` delegates to.

Also in the core: `TokenSet` (optional ready-made token type for the simple
case), `InMemoryTokenStore`, `Clock`, and `RelayStream<R>`. Several providers are
several `TokenManager<T>` instances held by the application.

Note (final review): `RelayStream` is internal and not exported from the
barrel. `authorizeStream` returns a plain `Stream<R>` with no access to the
replayed gRPC headers and trailers, so plan 2 (the gRPC adapter) needs an API
addition for them.

`validToken({rejected})`:

1. If the current token is valid (with `skew`) and not identical to `rejected`,
   return it.
2. If `rejected` is not identical to the current token, another call already
   refreshed; return the current token without a new refresh.
3. Otherwise start a refresh. All concurrent callers share one in-flight
   `Future`, cleared in `finally`.
4. `InvalidGrant`: clear the store, emit `Unauthenticated`, fail all waiters.
   `Transient`: keep the state and return the error to the caller; never log out.
5. Cancelling one waiter does not cancel the shared refresh.

`rejected` is compared by identity of the instance the manager issued through
`validToken`, so `T` does not need value equality.

Ordering and races: write to the store first, then emit state. A refresh that
completes after `logout` or `setTokens` is discarded. Tokens are read lazily
from the store on the first `validToken`, so no startup timer is needed. A
proactive background refresh is out of scope for the first release (phase 6).

`authorize` is the only place with replay logic: take `validToken()`, call
`send`, and on an auth failure call `validToken(rejected: used)` and replay
exactly once.

## 6. Adapters and streams

- **dio** (`DioTokenInterceptor<T>`): a plain `Interceptor`, not
  `QueuedInterceptor`, so only waiting for the token blocks. Replay goes through
  the user's own `Dio`, keeping their interceptors, adapter and timeouts, with a
  marker in `extra` that prevents re-entry. Refresh uses a separate client.
  `FormData` is cloned; stream bodies are not replayable, so the original error
  is returned. No `baseUrl` mutation.
- **package:http** (`HttpTokenClient<T> extends BaseClient`): wraps an inner
  `Client`. Replay works for `Request`; `StreamedRequest` and multipart bodies
  that cannot be recreated return the error without replay.
- **Streams** (gRPC responses): no `await for`. `RelayStream`
  creates a `StreamController` and manages the lifecycle:
  `onListen` obtains `validToken()` first, then opens the source and subscribes
  with `listen`; if the listener cancelled before the token arrived, the source
  is never opened; `onPause` and `onResume` are forwarded to the source
  subscription so backpressure is preserved; `onCancel` cancels the source,
  which cancels the gRPC call. An auth failure before the first
  event triggers one replay with a new token. After the first event the error is
  passed on and the application resubscribes using `states`, to avoid
  duplicates. gRPC client-streaming request streams are single-subscription and
  never replayed.
- **gRPC** (`GrpcTokenInterceptor<T>`): uses `RelayStream` and `authorize`; the
  dead `shouldRefresh` becomes a working `isAuthFailure`; errors on the
  `headers` and `trailers` futures of `AsyncResponseFuture` and
  `AsyncResponseStream` no longer escape unhandled.
- **gql** (`TokenManagerLink<T>`): a `Link` for `gql_link`, used by
  `graphql_flutter` and `ferry`. It is built on the core's `authorizeStream`
  for every operation it handles (not `authorize`, not `RelayStream` directly).
  An auth failure arrives on two channels: an error event
  (`ServerException.statusCode`) and a normal `Response` whose `errors` carry
  an auth code (`AuthFailureMatcher`); response-level failures are replayed
  only when `data == null`, because a mutation may already have run. Anonymous
  operations (login, sign-up) set the `SkipAuthorization` context entry and
  bypass the manager. Subscriptions are not handled by the link: WebSocket
  clients ignore HTTP headers, so `TokenManagerSocketAuth` provides
  `initialPayload` and `onConnectionLost` callbacks (default auth close code
  4401, configurable).

## 7. Migration

The old packages ship the new API together with a deprecated facade.

| Before | After |
|---|---|
| `TokenManager<T>(storage:, refreshDelegate:, infoDelegate:)` | same class; the constructor is `@Deprecated`, use `TokenManager.create` |
| `tokens` (sync getter), `tokensStream` | `@Deprecated`; use `current()` and `states` |
| `initialize()` | `@Deprecated`; loading is lazy |
| `waitForFresh`, `executeRefresh()` | `@Deprecated`; use `validToken()` |
| `setTokens(T?)` | kept; `null` logs out, prefer `logout()` |
| `TokenStorage<T>` (`getTokens`, `setTokens(T?)`) | `@Deprecated`; adapted into `TokenStore<T>` (not a typedef: the shapes differ) |
| `TokenManagerRefreshDelegate<T>.refresh()` | `@Deprecated`; adapted into `TokenRefresher<T>` |
| `refreshThreshold` | `skew` |
| `TokenInfoDelegate<T>` | `@Deprecated typedef` of `TokenInfo<T>` (same shape) |
| `RevokedTokensException` | `@Deprecated`; mapped to `InvalidGrant`; other exceptions map to `Transient` |
| `RefreshInterceptor<T>` (dio) | `@Deprecated` subclass of `DioTokenInterceptor<T>` (plan 2) |
| `RefreshInterceptor<T>` (grpc) | `@Deprecated` subclass of `GrpcTokenInterceptor<T>` (plan 2) |
| `applyTokensToRequest` | `applyTo` (plan 2) |

Behaviour changes that the facade cannot hide, recorded in `CHANGELOG.md` and
`doc/migration.md`: `refreshDelay` is ignored (no retry timer);
`initialize()` becomes a safe lazy read; a failed refresh no longer deadlocks:
`Transient` returns an error to the caller and `InvalidGrant` logs out.

The old API had no tests, so the facade is covered by new tests that follow the
documented behaviour. Versions are 0.1.0, so a breaking change is a minor bump
(0.2.0), and only changed packages are bumped, as in `typed_openapi`.

## 8. Style and tooling ported from typed_openapi

Ported (adapted to this repo). The Flutter widget lints `sized_box_shrink_expand`
and `use_colored_box` are dropped because the core is pure Dart.

- `analysis_options.yaml`: merge, do not overwrite. `lints/recommended` plus the
  explicit rule set of `typed_openapi`, `formatter: trailing_commas: preserve`.
  Web-compatibility rules are kept because dio, http and gql run on Flutter web.
  Gate: `dart analyze` reports no issues; no `// ignore:` without a reason.
- `CLAUDE.md`: rewritten for this repo with the sections Commands, Code rules,
  Code quality rules (limits table), Design rules, Where things are, Language
  (English).
- Size limits enforced by a ratchet test
  (`test/quality/size_limits_test.dart`, allowlist may only shrink): lib file 300
  lines, test file 500, method 40, parameters 5, nesting 3, about 15 members per
  class, one public class or sealed family per file, no `utils`/`helpers`/`common`,
  no `part`.
- Code rules: object-oriented, no top-level functions except `main`; no `!` and
  no `dynamic`; `catch` always with `on`, never catch `Error`; positive boolean
  names; `///` docs with a one-sentence summary and `[brackets]`; Dart 3.10
  features (dot shorthands, null-aware elements, switch expressions, records).
- Tests: `test/<area>/..._test.dart` mirrors `lib/src/<area>/`; shared
  `test/helpers/` (`FakeClock`, `FakeTokenStore`, `FakeRefresher`); no network;
  one behaviour per test; tests ship in the same commit as the code.
- `CONTRIBUTING.md`; Conventional Commits with a package scope; refactors in
  their own commit; per-package `CHANGELOG.md`.
- CI: `ci.yml` (format and analyze on stable and ubuntu; tests on the minimum
  SDK and stable; `fail-fast: false`; `permissions: contents: read`),
  `publish-dry-run`, and `publish.yml` triggered by tags `<pkg>-v*` through
  OIDC on pub.dev.
- Packaging: `resolution: workspace` moves into each `pubspec.yaml`; tracked
  `pubspec_overrides.yaml` files are removed.
- SDK floor raised from 3.7 to 3.10 (default; see section 9).

Not ported: the semver job and corpus tests (generator-specific),
`.superpowers/` workflows, `nightly.yml` and the web job (can be added later).

## 9. Roadmap

Work is test-driven. The regression test for each bug from section 2 is written
before the fix. Phases run in order; phase 3 packages are independent.

**Phase 0. Foundation.** Fix workspace resolution, raise the SDK, merge
`analysis_options.yaml`, add `CLAUDE.md`, `CONTRIBUTING.md`, the size ratchet
test, test helpers and `ci.yml`. Done when `dart analyze` is clean, CI is green
and `dart test` runs.

**Phase 1. Core (`token_manager`).** `TokenStore`, `TokenRefresher`, `TokenInfo`,
`AuthState`, `RefreshFailure`, `Clock`, `TokenManager`, `authorize`,
`RelayStream`, `InMemoryTokenStore`, `TokenSet`.
Regression tests: deadlock with a short-lived token, lost update, concurrent
`setTokens`/`logout`, `dispose` during a refresh, cancellation of one waiter.
Done when every core bug is reproduced by a test and fixed, and the core has no
dependency besides the SDK.

**Phase 2. Deprecated facade in the core.** Old `TokenManager<T>`,
`TokenStorage`, delegates and `RevokedTokensException` over the new core. Start
`doc/migration.md`.

**Phase 3. Adapters** (after phase 1):
1. `token_manager_dio`, with its deprecated subclass; tests on a stub
   `HttpClientAdapter`.
2. `token_manager_http`.
3. `token_manager_grpc` on `RelayStream`, with its deprecated subclass; tests on
   an in-process server, covering pause, resume and cancel.
4. `token_manager_gql`; tests with cancellation and WebSocket auth callbacks.

Done when every adapter has a test where concurrent 401s produce exactly one
refresh and one replay, and the stream adapters have a test where pause,
resume and cancel reach the source and no `await for` is used.

**Phase 4. Storage.** `token_manager_secure_storage` and
`token_manager_shared_preferences` with versioned serialisation. Done when
round-trip and version migration are covered by tests.

**Phase 5. Release.** READMEs, examples, `CHANGELOG.md`, finished
`doc/migration.md`, `publish.yml`, `dart pub publish --dry-run`. Publication
order: the core first, then adapters and storage by tag `<pkg>-v*`.

**Phase 6 (optional, later).** `ProactiveRefresher`, multi-isolate safety,
nightly CI, web job.

## 10. Risks and open decisions

Risks:

- Storage packages depend on Flutter plugins, so the shared workspace probably
  needs `flutter pub get`; the CI needs the Flutter SDK. Decide in phase 0 or 4.
- Multi-isolate use is not covered by in-memory single-flight (phase 6).

Open decisions (defaults in brackets):

- Raise the minimum SDK to 3.10 [yes]; otherwise drop dot shorthands and
  null-aware elements from the code rules.
- Remove the deprecated facade after two releases [two]; alternatives: one
  release, or keep until 1.0.
