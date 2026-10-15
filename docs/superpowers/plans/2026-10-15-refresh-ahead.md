# Refresh Ahead and `refreshIfNeeded` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an app avoid the one slow request that pays for a refresh: `TokenManager.create(refreshAhead:)` refreshes close-to-expiry tokens in the background, and `TokenManager.refreshIfNeeded({within})` refreshes at a moment the app chooses. Released as `token_manager` 0.2.3.

**Architecture:** `RefreshPolicy` learns a second, larger window (`refreshAhead`) and validates it. A new internal class `AheadRefresh` takes over from `TokenEngine` the work of starting refreshes (the blocking one, the background one with its one-attempt-per-tokens memory and error handling, and the one `refreshIfNeeded` waits for); all of them share the session's single flight and the existing epoch guard in `RefreshAttempt`. `TokenEngine` holds one `AheadRefresh` instead of the refresher and the policy, so its member count stays at 15 or fewer. No timer, no new public types, no adapter change.

**Tech Stack:** Dart 3.10 (pub workspace), `package:test`, `package:lints`. Pure Dart, no runtime dependencies.

**Spec:** `docs/superpowers/specs/2026-10-15-refresh-ahead-design.md` (the redesign it extends is `docs/superpowers/specs/2026-10-14-token-manager-redesign-design.md`). Executors read the spec and `CLAUDE.md` first.

## Global Constraints

- Release is `token_manager` **0.2.3**, a patch (additive change, decided with the user). Only `packages/token_manager` changes; the adapters' `^0.2.0` constraints still resolve and no adapter is edited or re-released.
- `CHANGELOG.md` entry with a bare `## 0.2.3` heading.
- `refreshAhead` is `null` by default and then behaviour is unchanged. When set it must be greater than `skew`; `TokenManager.create` throws an `ArgumentError` otherwise.
- No timer or scheduler (`Timer`, `RefreshScheduler`). The window is a fixed `Duration` (no `issuedAt`, no proportional window).
- No new public types and no new barrel export; `TokenManager` gets one parameter (`refreshAhead`) and one method (`refreshIfNeeded`). `AheadRefresh` is internal (`lib/src/engine/`).
- At most one refresh runs at a time; a background refresh and a blocking caller share one flight. A failed background refresh signs out only on `InvalidGrant` and never produces an unhandled error. A non-`Exception` `Error` is not caught.
- `dispose` does not bump the epoch and a refresh finishing after it is still persisted (rotated refresh tokens); after `dispose`, `validToken` starts no new background refresh.
- Size limits (`CLAUDE.md`): lib file 300 lines, test file 500, method 40, 5 parameters, nesting 3, class about 15 members. **`TokenEngine` must not grow past 15 members** (it has 15 now: constructor, 5 fields, 8 public members, `_clear`; count the constructor). `test/quality/size_limits_test.dart` is a ratchet: never add an allowlist entry.
- Code rules (`CLAUDE.md`): no top-level functions (except `main` in `example/` and tests), no `!`, no `dynamic`, `late` needs a comment, `catch` always has `on` and `Error` is never caught, no positional `bool` parameters, `///` doc comments with one summary sentence, relative imports inside a package, barrels untouched, never `await for` in library code.
- Every dart command runs under the memory guard, one package or one file at a time, never in parallel. The guard prefix is `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300`, written out in full in every command below.
- Commits: Conventional Commits with the package scope, a refactor is its own commit, trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Branch off `main`, run git from the repository root. Code, comments, docs and commit messages in English.
- Docs (recipe pages, README) compare approaches, never named products: avoid the words and phrases `better than`, `faster than`, `safer than`, `simpler than`, `cleaner than`, `unlike`, `compared to/with`, `alternative(s) to`, `vs`. A recipe page links to other files by absolute URL only (`https://github.com/4akloon/dart_token_manager/blob/main/...`).
- Known, deliberate exception: `TokenManager.create` ends up with 6 named parameters (the spec fixes `refreshAhead:` as a new `create` parameter). The engine and `RefreshPolicy` constructors stay within 5 (the engine takes a ready `RefreshPolicy`).

## Review Focus

The five failure modes the spec implies that a person using this software is most likely to hit, most likely first. Each has its test in the task that owns the code.

1. **Tokens whose lifetime is not much longer than `refreshAhead`** (for example a 4 minute token with `refreshAhead` of 5 minutes: every token the server issues is already inside the window). A successful background refresh that returns tokens still inside the window must not make every later call start another refresh. Expected: the new tokens are not refreshed ahead again and the blocking path takes over at `skew`. Test: Task 2, "a refresh that returns tokens still inside the window is not repeated".
2. **The token endpoint is down while tokens are inside the window.** Expected: one background attempt for those tokens, no retry per request, no thrown error, no unhandled error, the session stays `Authenticated`, and the blocking path retries at `skew`. A bug in the refresher (an `Error`) is not swallowed. Tests: Task 2, `token_engine_ahead_failure_test.dart` (Transient, other `Exception`, one attempt, retry at skew, `Error` surfaces).
3. **`refreshIfNeeded` on a cold start and around sign-out.** At app start nothing is loaded yet and the stored tokens may be about to expire; with no tokens, or no refresher, it must complete without error and without calling the refresher; a `logout` while it waits must not make it throw `NotAuthenticated`. Tests: Task 3, "loads the stored tokens first", "completes without a session", "completes without a refresher", "completes when a logout supersedes the refresh".
4. **`logout`, `setTokens` or `dispose` while a background refresh runs.** Expected: the refresh result is discarded after `logout`/`setTokens` (no resurrected session), persisted after `dispose` (the rotated refresh token is not lost), and `dispose` stops new background refreshes. Tests: Task 2, `token_engine_ahead_failure_test.dart`.
5. **Tokens that never expire, or no refresher, with `refreshAhead` set.** Expected: nothing is refreshed and nothing throws. Tests: Task 1 (`RefreshPolicy`), Task 2 ("tokens that never expire are not refreshed ahead", "refreshAhead without a refresher changes nothing").

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `packages/token_manager/lib/src/engine/refresh_policy.dart` | modify | Both windows: `isExpiring(tokens, window)`, `needsRefresh`, `needsAheadRefresh`, `window`; validates `refreshAhead > skew` |
| `packages/token_manager/lib/src/engine/ahead_refresh.dart` | **create** | Starts refreshes over the session's single flight: `dueFlight`, `startAhead` (one attempt per tokens, error handling), `ifNeeded` |
| `packages/token_manager/lib/src/engine/token_engine.dart` | modify | Takes a `RefreshPolicy`; holds an `AheadRefresh` instead of `_refresher`/`_policy`; gains `refreshIfNeeded` |
| `packages/token_manager/lib/src/engine/session.dart`, `replay_value.dart` | modify | `isClosed` getter so the engine can tell it was disposed |
| `packages/token_manager/lib/src/token_manager.dart` | modify | `create(refreshAhead:)`, `refreshIfNeeded`, docs |
| `packages/token_manager/example/recipes/refresh_on_resume.dart` | **create** | Compiled recipe code |
| `packages/token_manager/doc/recipes/refresh_on_resume.md` | **create** | Recipe page |
| `packages/token_manager/doc/{concepts,refreshing,getting_started,migration}.md`, `doc/recipes/session_expiry.md`, `README.md` | modify | Replace the "no background timer" wording |
| `packages/token_manager/dartdoc_options.yaml`, `docs/recipes.md`, `llms.txt` | modify | Register the new recipe |
| `packages/token_manager/pubspec.yaml`, `CHANGELOG.md` | modify | 0.2.3 |
| `packages/token_manager/test/helpers/engine_fixture.dart` | modify | Builds engines from a `RefreshPolicy`; `refreshAhead` option |
| `packages/token_manager/test/helpers/uncaught_errors.dart` | **create** | Collects errors nobody handled during a body |
| `packages/token_manager/test/engine/{refresh_policy,session,replay_value}_test.dart` | modify | New behaviours |
| `packages/token_manager/test/engine/token_engine_ahead_test.dart`, `token_engine_ahead_failure_test.dart`, `token_engine_if_needed_test.dart` | **create** | Engine behaviour (each under 500 lines) |
| `packages/token_manager/test/token_manager_test.dart` | modify | `create` validation, passthroughs |
| `packages/token_manager/test/recipes/refresh_on_resume_test.dart` | **create** | Recipe behaviours |

`TokenEngine` member count by task: now 15; after Task 2 it has 14 (constructor, `_store`, `_session`, `_refresh`, `_loader`, `states`, `state`, `current`, `validToken`, `pendingRefresh`, `setTokens`, `logout`, `dispose`, `_clear`); after Task 3 it has 15 (adds `refreshIfNeeded`). The spec names an engine method `refreshInBackground`; to keep the engine at 15 that method lives on `AheadRefresh` as `startAhead` and the engine calls it. The behaviour the spec asks of it (own error handling, `validToken` never returns or awaits the future) is unchanged.

---

### Task 1: `RefreshPolicy` window and `create` validation

Two commits: first a refactor (the engine receives a ready `RefreshPolicy`, which keeps the engine constructor at 3 parameters when the window arrives), then the feature.

**Files:**
- Modify: `packages/token_manager/lib/src/engine/refresh_policy.dart`
- Modify: `packages/token_manager/lib/src/engine/token_engine.dart` (constructor and imports only)
- Modify: `packages/token_manager/lib/src/token_manager.dart` (both constructors, import)
- Modify: `packages/token_manager/test/helpers/engine_fixture.dart`
- Test: `packages/token_manager/test/engine/refresh_policy_test.dart`, `packages/token_manager/test/token_manager_test.dart`

**Interfaces:**
- Consumes: existing `RefreshPolicy.needsRefresh(T tokens, T? rejected)`, `Clock`, `TokenInfo<T>`.
- Produces (used by Tasks 2 and 3):
  - `RefreshPolicy<T>({required Duration skew, required Clock clock, Duration? refreshAhead, TokenInfo<T>? info})`, no longer `const`, throws `ArgumentError` (name `refreshAhead`) when `refreshAhead != null && refreshAhead <= skew`.
  - `bool isExpiring(T tokens, Duration window)`: true when less than or exactly `window` is left; false when `info` is null or says `null`.
  - `bool needsAheadRefresh(T tokens)`: false without `refreshAhead`, else `isExpiring(tokens, refreshAhead)`.
  - `Duration get window`: `refreshAhead ?? skew` (the default `within` of `refreshIfNeeded`).
  - `TokenEngine<T>({required TokenStore<T> store, required RefreshPolicy<T> policy, TokenRefresher<T>? refresher})`.
  - `TokenManager.create({..., Duration? refreshAhead, ...})`.
  - `EngineFixture.engine({bool withRefresher = true, Duration? refreshAhead})`.

#### Part A: refactor, the engine takes a `RefreshPolicy`

- [ ] **Step 1: Change the engine constructor**

In `packages/token_manager/lib/src/engine/token_engine.dart`, replace the constructor:

```dart
  /// Creates an engine over [store].
  TokenEngine({
    required TokenStore<T> store,
    required Duration skew,
    required Clock clock,
    TokenRefresher<T>? refresher,
    TokenInfo<T>? info,
  }) : _store = store,
       _refresher = refresher,
       _policy = RefreshPolicy<T>(skew: skew, clock: clock, info: info);
```

with:

```dart
  /// Creates an engine over [store] that refreshes as [policy] decides.
  TokenEngine({
    required TokenStore<T> store,
    required RefreshPolicy<T> policy,
    TokenRefresher<T>? refresher,
  }) : _store = store,
       _refresher = refresher,
       _policy = policy;
```

and delete the now unused imports `import '../clock.dart';` and `import '../token_info.dart';`.

- [ ] **Step 2: Update the manager's two constructors**

In `packages/token_manager/lib/src/token_manager.dart` add `import 'engine/refresh_policy.dart';` (keep the imports sorted: after `engine/authorized_call.dart`, before `engine/relay_stream.dart`). Replace the engine construction of the deprecated constructor:

```dart
  }) : _engine = TokenEngine<T>(
         store: StorageTokenStore<T>(storage),
         policy: RefreshPolicy<T>(
           skew: refreshDelegate?.refreshThreshold ?? const Duration(minutes: 3),
           clock: const Clock(),
           info: infoDelegate,
         ),
         refresher: refreshDelegate == null
             ? null
             : DelegateTokenRefresher<T>(refreshDelegate),
       );
```

and of `TokenManager.create`:

```dart
  }) : _engine = TokenEngine<T>(
         store: store,
         policy: RefreshPolicy<T>(skew: skew, clock: clock, info: info),
         refresher: refresher,
       );
```

- [ ] **Step 3: Update the test fixture**

In `packages/token_manager/test/helpers/engine_fixture.dart` add `import 'package:token_manager/src/engine/refresh_policy.dart';` (sorted before `token_engine.dart`) and replace `engine`:

```dart
  /// Builds an engine with a 30 second skew.
  TokenEngine<TokenSet> engine({bool withRefresher = true}) {
    return TokenEngine<TokenSet>(
      store: store,
      policy: RefreshPolicy<TokenSet>(
        skew: const Duration(seconds: 30),
        clock: clock,
        info: const TokenSetInfo(),
      ),
      refresher: withRefresher ? refresher : null,
    );
  }
```

- [ ] **Step 4: Run the existing tests; nothing changed in behaviour**

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
Expected: all tests pass.

- [ ] **Step 5: Format, analyze**

Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart format packages`
Expected: formatting applied, then a second identical run reports `Formatted ... (0 changed)`.

Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 6: Commit the refactor**

```bash
git add packages/token_manager/lib packages/token_manager/test/helpers/engine_fixture.dart
git commit -m "refactor(token_manager): hand the refresh policy to the engine

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

#### Part B: the `refreshAhead` window

- [ ] **Step 7: Write the failing policy tests**

In `packages/token_manager/test/engine/refresh_policy_test.dart` replace the `policy` helper with a version that takes `refreshAhead`:

```dart
  RefreshPolicy<List<int>> policy({
    DateTime? expiry,
    FakeClock? clock,
    Duration? refreshAhead,
  }) {
    return RefreshPolicy<List<int>>(
      skew: skew,
      refreshAhead: refreshAhead,
      clock: clock ?? FakeClock(start),
      info: expiry == null ? null : _FixedInfo(expiry),
    );
  }
```

and append before the closing `}` of `main`:

```dart
  group('isExpiring', () {
    test('is true when less than the window is left', () {
      final subject = policy(expiry: start.add(const Duration(minutes: 2)));

      expect(subject.isExpiring([1], const Duration(minutes: 3)), isTrue);
    });

    test('is false when more than the window is left', () {
      final subject = policy(expiry: start.add(const Duration(minutes: 2)));

      expect(subject.isExpiring([1], const Duration(minutes: 1)), isFalse);
    });

    test('is true exactly at the window boundary', () {
      final subject = policy(expiry: start.add(const Duration(minutes: 2)));

      expect(subject.isExpiring([1], const Duration(minutes: 2)), isTrue);
    });

    test('is false for tokens that never expire', () {
      expect(policy().isExpiring([1], const Duration(days: 365)), isFalse);
    });
  });

  group('needsAheadRefresh', () {
    const ahead = Duration(minutes: 5);

    test('is false without a refreshAhead window', () {
      final subject = policy(expiry: start.add(const Duration(minutes: 1)));

      expect(subject.needsAheadRefresh([1]), isFalse);
    });

    test('is true inside the window', () {
      final subject = policy(
        expiry: start.add(const Duration(minutes: 3)),
        refreshAhead: ahead,
      );

      expect(subject.needsAheadRefresh([1]), isTrue);
    });

    test('is true exactly at the window boundary', () {
      final subject = policy(expiry: start.add(ahead), refreshAhead: ahead);

      expect(subject.needsAheadRefresh([1]), isTrue);
    });

    test('is false outside the window', () {
      final subject = policy(
        expiry: start.add(const Duration(minutes: 6)),
        refreshAhead: ahead,
      );

      expect(subject.needsAheadRefresh([1]), isFalse);
    });

    test('is false for tokens that never expire', () {
      expect(policy(refreshAhead: ahead).needsAheadRefresh([1]), isFalse);
    });
  });

  group('window', () {
    test('is the skew without a refreshAhead window', () {
      expect(policy().window, skew);
    });

    test('is refreshAhead when set', () {
      expect(
        policy(refreshAhead: const Duration(minutes: 5)).window,
        const Duration(minutes: 5),
      );
    });
  });

  group('refreshAhead validation', () {
    test('equal to the skew is rejected', () {
      expect(
        () => policy(refreshAhead: skew),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'refreshAhead',
          ),
        ),
      );
    });

    test('shorter than the skew is rejected', () {
      expect(
        () => policy(refreshAhead: const Duration(seconds: 10)),
        throwsArgumentError,
      );
    });

    test('longer than the skew is accepted', () {
      expect(
        () => policy(refreshAhead: const Duration(seconds: 31)),
        returnsNormally,
      );
    });
  });
```

- [ ] **Step 8: Write the failing manager tests**

In `packages/token_manager/test/token_manager_test.dart` append before the closing `}` of `main`:

```dart
  test('create rejects a refreshAhead that equals the skew', () {
    expect(
      () => TokenManager<TokenSet>.create(
        store: store,
        refreshAhead: const Duration(seconds: 30),
      ),
      throwsArgumentError,
    );
  });

  test('create checks refreshAhead against a custom skew', () {
    expect(
      () => TokenManager<TokenSet>.create(
        store: store,
        skew: const Duration(minutes: 2),
        refreshAhead: const Duration(seconds: 90),
      ),
      throwsArgumentError,
    );
  });

  test('create accepts a refreshAhead greater than the skew', () {
    expect(
      () => TokenManager<TokenSet>.create(
        store: store,
        refreshAhead: const Duration(minutes: 5),
      ),
      returnsNormally,
    );
  });
```

- [ ] **Step 9: Run the tests to verify they fail**

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/engine/refresh_policy_test.dart`
Expected: compile error, `refreshAhead` is not a named parameter of `RefreshPolicy` (and `isExpiring`, `needsAheadRefresh`, `window` are undefined).

- [ ] **Step 10: Implement `RefreshPolicy`**

Replace `packages/token_manager/lib/src/engine/refresh_policy.dart`:

```dart
import '../clock.dart';
import '../token_info.dart';

/// Decides whether tokens must be refreshed before they are handed out, or
/// should be refreshed in the background.
final class RefreshPolicy<T> {
  /// Creates a policy that refreshes [skew] before expiry as told by [info].
  ///
  /// With [refreshAhead] set, tokens that expire within it are also due for a
  /// background refresh. It must be greater than [skew], or an
  /// [ArgumentError] is thrown.
  RefreshPolicy({
    required Duration skew,
    required Clock clock,
    Duration? refreshAhead,
    TokenInfo<T>? info,
  }) : _skew = skew,
       _refreshAhead = refreshAhead,
       _clock = clock,
       _info = info {
    if (refreshAhead != null && refreshAhead <= skew) {
      throw ArgumentError.value(
        refreshAhead,
        'refreshAhead',
        'must be greater than skew ($skew)',
      );
    }
  }

  final Duration _skew;
  final Duration? _refreshAhead;
  final Clock _clock;
  final TokenInfo<T>? _info;

  /// The margin used when a caller names none: the refresh-ahead window when
  /// set, else the skew.
  Duration get window => _refreshAhead ?? _skew;

  /// Whether [tokens] must be refreshed first.
  ///
  /// True when [tokens] are the very [rejected] instance a server refused, or
  /// when they expire within the skew.
  bool needsRefresh(T tokens, T? rejected) {
    return identical(tokens, rejected) || isExpiring(tokens, _skew);
  }

  /// Whether [tokens] are due for a background refresh.
  ///
  /// Always false without a refresh-ahead window.
  bool needsAheadRefresh(T tokens) {
    final ahead = _refreshAhead;
    return ahead != null && isExpiring(tokens, ahead);
  }

  /// Whether [tokens] expire within [window] of now; never for tokens without
  /// an expiry.
  bool isExpiring(T tokens, Duration window) {
    final expiresAt = _info?.expiresAt(tokens);
    if (expiresAt == null) {
      return false;
    }
    return !_clock.now().add(window).isBefore(expiresAt);
  }
}
```

- [ ] **Step 11: Add `refreshAhead` to `create` and the fixture**

In `packages/token_manager/lib/src/token_manager.dart` replace the `create` doc and signature and engine construction:

```dart
  /// Creates a manager over [store].
  ///
  /// Tokens are refreshed with [refresher] when [info] says they expire within
  /// [skew], or when a server rejects them. With [refreshAhead] set, tokens
  /// that expire within it are also refreshed in the background by the next
  /// [validToken]; it must be greater than [skew], or an [ArgumentError] is
  /// thrown. Without a [refresher] tokens are never refreshed; without [info]
  /// they never expire.
  TokenManager.create({
    required TokenStore<T> store,
    TokenRefresher<T>? refresher,
    TokenInfo<T>? info,
    Duration skew = const Duration(seconds: 30),
    Duration? refreshAhead,
    Clock clock = const Clock(),
  }) : _engine = TokenEngine<T>(
         store: store,
         policy: RefreshPolicy<T>(
           skew: skew,
           refreshAhead: refreshAhead,
           clock: clock,
           info: info,
         ),
         refresher: refresher,
       );
```

In `packages/token_manager/test/helpers/engine_fixture.dart` replace `engine` with the version that takes the window:

```dart
  /// Builds an engine with a 30 second skew and, when given, a refresh-ahead
  /// window.
  TokenEngine<TokenSet> engine({
    bool withRefresher = true,
    Duration? refreshAhead,
  }) {
    return TokenEngine<TokenSet>(
      store: store,
      policy: RefreshPolicy<TokenSet>(
        skew: const Duration(seconds: 30),
        refreshAhead: refreshAhead,
        clock: clock,
        info: const TokenSetInfo(),
      ),
      refresher: withRefresher ? refresher : null,
    );
  }
```

- [ ] **Step 12: Run the tests to verify they pass**

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/engine/refresh_policy_test.dart`
Expected: all pass.

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/token_manager_test.dart`
Expected: all pass.

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
Expected: all pass (including `test/quality/size_limits_test.dart`).

- [ ] **Step 13: Format, analyze, commit**

Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart format packages` (run it a second time: 0 changed)
Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart analyze packages` (expected `No issues found!`)

```bash
git add packages/token_manager/lib packages/token_manager/test
git commit -m "feat(token_manager): add the refreshAhead window to RefreshPolicy and create

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `AheadRefresh` and the background refresh

Two commits: a refactor that moves the starting of refreshes out of `TokenEngine` into `AheadRefresh` (no behaviour change, frees members for Task 3), then the feature.

**Files:**
- Create: `packages/token_manager/lib/src/engine/ahead_refresh.dart`
- Modify: `packages/token_manager/lib/src/engine/token_engine.dart`
- Modify: `packages/token_manager/lib/src/engine/session.dart`, `packages/token_manager/lib/src/engine/replay_value.dart`
- Modify: `packages/token_manager/lib/src/token_manager.dart` (`validToken` doc)
- Create: `packages/token_manager/test/helpers/uncaught_errors.dart`
- Create: `packages/token_manager/test/engine/token_engine_ahead_test.dart`, `packages/token_manager/test/engine/token_engine_ahead_failure_test.dart`
- Modify: `packages/token_manager/test/engine/session_test.dart`, `packages/token_manager/test/engine/replay_value_test.dart`, `packages/token_manager/test/token_manager_test.dart`

**Interfaces:**
- Consumes (Task 1): `RefreshPolicy.needsRefresh`, `needsAheadRefresh`; `TokenEngine({store, policy, refresher})`; `EngineFixture.engine({withRefresher, refreshAhead})`.
- Produces (used by Task 3):
  - `AheadRefresh<T>({required Session<T> session, required TokenStore<T> store, required RefreshPolicy<T> policy, TokenRefresher<T>? refresher})`.
  - `Future<T>? dueFlight(T tokens, T? rejected)`: `null` when the tokens can be used now (no refresher, or no refresh due); otherwise the running flight or a new one.
  - `void startAhead(T tokens)`: starts a background refresh if due; never throws, returns nothing.
  - `Session<T>.isClosed`, `ReplayValue<S>.isClosed`.
  - `UncaughtErrors().during(Future<void> Function() body)` returning `Future<List<Object>>`.

#### Part A: refactor, `AheadRefresh` owns starting a refresh

- [ ] **Step 1: Create `AheadRefresh` with the blocking path only**

Create `packages/token_manager/lib/src/engine/ahead_refresh.dart`:

```dart
import '../token_refresher.dart';
import '../token_store.dart';
import 'refresh_attempt.dart';
import 'refresh_policy.dart';
import 'session.dart';

/// Starts the refreshes of one engine over the session's single flight.
final class AheadRefresh<T> {
  /// Creates a starter that refreshes with [refresher] as [policy] decides.
  ///
  /// Without a [refresher] nothing is ever refreshed.
  AheadRefresh({
    required Session<T> session,
    required TokenStore<T> store,
    required RefreshPolicy<T> policy,
    TokenRefresher<T>? refresher,
  }) : _session = session,
       _store = store,
       _policy = policy,
       _refresher = refresher;

  final Session<T> _session;
  final TokenStore<T> _store;
  final RefreshPolicy<T> _policy;
  final TokenRefresher<T>? _refresher;

  /// The refresh [tokens] must wait for, or `null` when they can be used now.
  ///
  /// A refresh is due when [tokens] are the [rejected] ones or expire within
  /// the skew. It joins the refresh in flight, or starts one.
  Future<T>? dueFlight(T tokens, T? rejected) {
    final refresher = _refresher;
    if (refresher == null || !_policy.needsRefresh(tokens, rejected)) {
      return null;
    }
    return _flight(refresher, tokens);
  }

  Future<T> _flight(TokenRefresher<T> refresher, T tokens) {
    final running = _session.flight;
    if (running != null) {
      return running;
    }
    final flight = RefreshAttempt<T>(
      session: _session,
      store: _store,
      refresher: refresher,
      current: tokens,
    ).run();
    _session.track(flight);
    return flight;
  }
}
```

- [ ] **Step 2: Make the engine use it**

In `packages/token_manager/lib/src/engine/token_engine.dart`: replace the imports `refresh_attempt.dart` and `refresh_policy.dart` with `ahead_refresh.dart` and `refresh_policy.dart` (still needed for the constructor type), drop the `_refresher` and `_policy` fields, and replace the constructor, the field block and `validToken`.

Constructor and fields (the `_loader` field and everything below it stay as they are):

```dart
  /// Creates an engine over [store] that refreshes as [policy] decides.
  TokenEngine({
    required TokenStore<T> store,
    required RefreshPolicy<T> policy,
    TokenRefresher<T>? refresher,
  }) : _store = store {
    _refresh = AheadRefresh<T>(
      session: _session,
      store: store,
      policy: policy,
      refresher: refresher,
    );
  }

  final TokenStore<T> _store;
  final Session<T> _session = Session<T>();

  // late: it reads this engine's session, which exists only after the
  // initializer list has run.
  late final AheadRefresh<T> _refresh;
```

`validToken`:

```dart
  Future<T> validToken({T? rejected}) async {
    await _loader.load();
    final tokens = state.tokensOrNull;
    if (tokens == null) {
      throw const NotAuthenticated();
    }
    return _refresh.dueFlight(tokens, rejected) ?? tokens;
  }
```

Keep the `Future<T>` return type: `dueFlight(...) ?? tokens` is `FutureOr<T>`, valid in an `async` function.

- [ ] **Step 3: Run the tests; behaviour is unchanged**

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
Expected: all pass.

- [ ] **Step 4: Format, analyze, commit**

Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart format packages` (twice; second run 0 changed)
Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart analyze packages` (expected `No issues found!`)

```bash
git add packages/token_manager/lib
git commit -m "refactor(token_manager): move starting a refresh out of TokenEngine

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

#### Part B: the background refresh

- [ ] **Step 5: Write the failing `isClosed` tests**

Append to `packages/token_manager/test/engine/replay_value_test.dart` (before the final `}` of `main`):

```dart
  test('isClosed is false until close and true after', () async {
    final replay = ReplayValue<int>(1);
    expect(replay.isClosed, isFalse);

    await replay.close();

    expect(replay.isClosed, isTrue);
  });
```

Append to `packages/token_manager/test/engine/session_test.dart` (before the final `}` of `main`):

```dart
  test('isClosed follows close', () async {
    expect(session.isClosed, isFalse);

    await session.close();

    expect(session.isClosed, isTrue);
  });
```

- [ ] **Step 6: Add the test helper that collects unhandled errors**

Create `packages/token_manager/test/helpers/uncaught_errors.dart`:

```dart
import 'dart:async';

/// Runs a body in a zone and reports the errors nobody handled.
final class UncaughtErrors {
  /// Creates the collector.
  const UncaughtErrors();

  /// Runs [body], lets the event queue settle and returns the errors that
  /// reached the zone's uncaught-error handler, those of [body] included.
  ///
  /// Keep `expect` calls out of [body]: a failed one would be collected here
  /// instead of failing the test.
  Future<List<Object>> during(Future<void> Function() body) async {
    final errors = <Object>[];
    final finished = Completer<void>();
    unawaited(
      runZonedGuarded(() async {
        try {
          await body();
        } finally {
          finished.complete();
        }
      }, (error, stack) => errors.add(error)),
    );
    await finished.future;
    await Future<void>.delayed(Duration.zero);
    return errors;
  }
}
```

- [ ] **Step 7: Write the failing engine tests (windows and sharing)**

Create `packages/token_manager/test/engine/token_engine_ahead_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';

void main() {
  const ahead = Duration(minutes: 5);
  // Between the 30 second skew and the 5 minute window.
  const inWindow = Duration(minutes: 3);
  // Assigned in setUp, which runs before every test.
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('tokens with more than refreshAhead left are not refreshed', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(const Duration(minutes: 10));
    await engine.setTokens(current);

    expect(await engine.validToken(), same(current));
    await settle();

    expect(fixture.refresher.callCount, 0);
  });

  test('tokens inside the window are returned at once and refreshed', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    expect(await engine.validToken(), same(current));
    await settle();
    expect(fixture.refresher.callCount, 1);
    expect(engine.state, isA<Refreshing<TokenSet>>());
    fixture.refresher.complete(fresh);
    await settle();

    expect(engine.state, isA<Authenticated<TokenSet>>());
    expect(engine.state.tokensOrNull, same(fresh));
    expect(fixture.store.stored, same(fresh));
  });

  test('ten concurrent callers inside the window start one refresh', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);

    final results = await Future.wait([
      for (var i = 0; i < 10; i++) engine.validToken(),
    ]);
    await settle();

    expect(results, everyElement(same(current)));
    expect(fixture.refresher.callCount, 1);
  });

  test('a caller inside the skew joins the background refresh', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    await engine.validToken();
    fixture.clock.advance(const Duration(minutes: 2, seconds: 45));

    final blocked = engine.validToken();
    await settle();
    fixture.refresher.complete(fresh);

    expect(await blocked, same(fresh));
    expect(fixture.refresher.callCount, 1);
  });

  test('without refreshAhead the window changes nothing', () async {
    final engine = fixture.engine();
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);

    expect(await engine.validToken(), same(current));
    await settle();

    expect(fixture.refresher.callCount, 0);
  });

  test('tokens refreshed ahead can be refreshed ahead again later', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    await engine.validToken();
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    fixture.refresher.complete(fresh);
    await settle();

    fixture.clock.advance(const Duration(minutes: 56));
    await engine.validToken();
    await settle();

    expect(fixture.refresher.callCount, 2);
    expect(fixture.refresher.requested.last, same(fresh));
  });

  test(
    'a refresh that returns tokens still inside the window is not repeated',
    () async {
      final engine = fixture.engine(refreshAhead: ahead);
      await engine.setTokens(fixture.tokens(inWindow));
      await engine.validToken();
      final stillSoon = fixture.tokens(const Duration(minutes: 4), access: 'b');
      fixture.refresher.complete(stillSoon);
      await settle();

      expect(await engine.validToken(), same(stillSoon));
      expect(await engine.validToken(), same(stillSoon));
      await settle();

      expect(fixture.refresher.callCount, 1);
    },
  );

  test('tokens that never expire are not refreshed ahead', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    const forever = TokenSet(accessToken: 'a');
    await engine.setTokens(forever);

    expect(await engine.validToken(), same(forever));
    await settle();

    expect(fixture.refresher.callCount, 0);
  });

  test('refreshAhead without a refresher changes nothing', () async {
    final engine = fixture.engine(withRefresher: false, refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);

    expect(await engine.validToken(), same(current));
    await settle();

    expect(fixture.refresher.callCount, 0);
  });
}
```

- [ ] **Step 8: Write the failing engine tests (failures, epoch, dispose)**

Create `packages/token_manager/test/engine/token_engine_ahead_failure_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/refresh_failure.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';
import '../helpers/uncaught_errors.dart';

void main() {
  const ahead = Duration(minutes: 5);
  // Between the 30 second skew and the 5 minute window.
  const inWindow = Duration(minutes: 3);
  const watch = UncaughtErrors();
  // Assigned in setUp, which runs before every test.
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a Transient background failure is swallowed, the session stays', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);

    final uncaught = await watch.during(() async {
      await engine.validToken();
      fixture.refresher.fail(const Transient('offline'));
      await settle();
    });

    expect(uncaught, isEmpty);
    expect(engine.state, isA<Authenticated<TokenSet>>());
    expect(engine.state.tokensOrNull, same(current));
    expect(fixture.store.deletes, 0);
  });

  test('a background failure that is not a RefreshFailure is swallowed', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);

    final uncaught = await watch.during(() async {
      await engine.validToken();
      fixture.refresher.fail(const FormatException('bad body'));
      await settle();
    });

    expect(uncaught, isEmpty);
    expect(engine.state, isA<Authenticated<TokenSet>>());
    expect(engine.state.tokensOrNull, same(current));
  });

  test('the same tokens get one background attempt, not one per call', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));

    await watch.during(() async {
      await engine.validToken();
      fixture.refresher.fail(const Transient('offline'));
      await settle();
      await engine.validToken();
      await engine.validToken();
      await settle();
    });

    expect(fixture.refresher.callCount, 1);
  });

  test('the blocking path retries once the tokens reach the skew', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    await watch.during(() async {
      await engine.validToken();
      fixture.refresher.fail(const Transient('offline'));
      await settle();
    });
    fixture.clock.advance(const Duration(minutes: 2, seconds: 45));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final retry = engine.validToken();
    await settle();
    fixture.refresher.complete(fresh, call: 1);

    expect(await retry, same(fresh));
    expect(fixture.refresher.callCount, 2);
  });

  test('InvalidGrant in the background ends the session', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));

    final uncaught = await watch.during(() async {
      await engine.validToken();
      fixture.refresher.fail(const InvalidGrant());
      await settle();
    });

    expect(uncaught, isEmpty);
    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('an Error from the refresher is not swallowed', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);

    final uncaught = await watch.during(() async {
      await engine.validToken();
      fixture.refresher.fail(StateError('bug in the refresher'));
      await settle();
    });

    expect(uncaught, hasLength(1));
    expect(uncaught.single, isA<StateError>());
    expect(engine.state, isA<Authenticated<TokenSet>>());
    expect(engine.state.tokensOrNull, same(current));
  });

  test('logout during the background refresh discards its result', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));

    final uncaught = await watch.during(() async {
      await engine.validToken();
      await engine.logout();
      fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
      await settle();
    });

    expect(uncaught, isEmpty);
    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('setTokens during the background refresh discards its result', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    final loggedIn = fixture.tokens(const Duration(hours: 2), access: 'login');

    final uncaught = await watch.during(() async {
      await engine.validToken();
      await engine.setTokens(loggedIn);
      fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
      await settle();
    });

    expect(uncaught, isEmpty);
    expect(fixture.store.stored, same(loggedIn));
    expect(engine.state.tokensOrNull, same(loggedIn));
  });

  test('no background refresh starts after dispose', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);
    await engine.dispose();

    expect(await engine.validToken(), same(current));
    await settle();

    expect(fixture.refresher.callCount, 0);
  });

  test('a background refresh running at dispose is still persisted', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    await engine.validToken();

    await engine.dispose();
    fixture.refresher.complete(fresh);
    await settle();

    expect(fixture.store.stored, same(fresh));
    expect(engine.state.tokensOrNull, same(fresh));
  });
}
```

Several test names above exceed 80 columns; `dart format` in Step 15 wraps them.

- [ ] **Step 9: Write the failing manager test**

In `packages/token_manager/test/token_manager_test.dart` append before the closing `}` of `main`:

```dart
  test('create with refreshAhead refreshes close-to-expiry tokens in the '
      'background', () async {
    final eager = TokenManager<TokenSet>.create(
      store: store,
      refresher: refresher,
      info: const TokenSetInfo(),
      refreshAhead: const Duration(minutes: 5),
      clock: clock,
    );
    final soon = tokens(const Duration(minutes: 3));
    await eager.setTokens(soon);

    expect(await eager.validToken(), same(soon));
    expect(refresher.callCount, 1);
  });
```

- [ ] **Step 10: Run the new tests to verify they fail**

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/engine/replay_value_test.dart`
Expected: compile error, `isClosed` is not defined for `ReplayValue`.

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/engine/token_engine_ahead_test.dart`
Expected: FAIL, the in-window tests report `callCount` 0 instead of 1 (the window is not used yet).

- [ ] **Step 11: Implement `isClosed`**

In `packages/token_manager/lib/src/engine/replay_value.dart`, after the `value` getter add:

```dart
  /// Whether [close] was called.
  bool get isClosed => _controller.isClosed;
```

In `packages/token_manager/lib/src/engine/session.dart`, after the `flight` getter add:

```dart
  /// Whether [close] was called.
  bool get isClosed => _states.isClosed;
```

- [ ] **Step 12: Implement `startAhead`**

In `packages/token_manager/lib/src/engine/ahead_refresh.dart` add `import 'dart:async';` as the first import, add the field after `_refresher`:

```dart
  // The tokens a background refresh was last started for: one attempt per
  // tokens object, so a failing server is not hit by every request.
  T? _attempted;
```

and add this method and helper after `dueFlight` (before `_flight`):

```dart
  /// Starts a background refresh of [tokens] when they are inside the window.
  ///
  /// Does nothing without a refresher or a window, after the session was
  /// disposed, while a refresh is in flight, or for tokens already tried. The
  /// refresh's failures are handled here: a failure that is an `Exception` is
  /// dropped (the attempt already restored the state, or ended the session on
  /// `InvalidGrant`); an `Error` is not caught.
  void startAhead(T tokens) {
    final refresher = _refresher;
    if (refresher == null ||
        _session.isClosed ||
        _session.flight != null ||
        identical(_attempted, tokens) ||
        !_policy.needsAheadRefresh(tokens)) {
      return;
    }
    _attempted = tokens;
    unawaited(
      _flight(refresher, tokens)
          .then<void>(_guardAgainstLoop)
          .catchError((_) {}, test: (error) => error is Exception),
    );
  }

  /// Marks tokens that a refresh returned inside the window as tried, so that
  /// a short-lived token does not start a refresh on every call.
  void _guardAgainstLoop(T refreshed) {
    if (_policy.needsAheadRefresh(refreshed)) {
      _attempted = refreshed;
    }
  }
```

Update the class doc to: `/// Starts the refreshes of one engine over the session's single flight: the one a caller waits for and the one that runs ahead of expiry.`

- [ ] **Step 13: Call it from `validToken`**

In `packages/token_manager/lib/src/engine/token_engine.dart` replace the last line of `validToken` and extend its doc:

```dart
  /// Returns tokens that are valid now, refreshing them when needed.
  ///
  /// [rejected] is a token a server just refused: it forces a refresh unless
  /// another caller already replaced it. Concurrent callers share one refresh.
  /// Tokens that are valid but inside the refresh-ahead window are returned at
  /// once and refreshed in the background.
  Future<T> validToken({T? rejected}) async {
    await _loader.load();
    final tokens = state.tokensOrNull;
    if (tokens == null) {
      throw const NotAuthenticated();
    }
    final due = _refresh.dueFlight(tokens, rejected);
    if (due != null) {
      return due;
    }
    _refresh.startAhead(tokens);
    return tokens;
  }
```

In `packages/token_manager/lib/src/token_manager.dart` add to the `validToken` doc a last sentence: `With refreshAhead set, tokens that are close to expiry are returned at once and refreshed in the background.`

- [ ] **Step 14: Run the tests to verify they pass**

Run each, one at a time (all expected to pass):

`cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/engine/token_engine_ahead_test.dart`
`cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/engine/token_engine_ahead_failure_test.dart`
`cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/engine/session_test.dart`
`cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/engine/replay_value_test.dart`
`cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/token_manager_test.dart`

If "the same tokens get one background attempt" or the retry test fails, check the first failure: `_attempted` must be set before `_flight` is called, and `_session.flight` must be non-null right after `_flight` returns (`Session.track` sets it synchronously).

Then the whole package: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
Expected: all pass, including `test/quality/size_limits_test.dart`.

- [ ] **Step 15: Format, analyze, commit**

Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart format packages` (twice; the second run must change 0 files)
Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart analyze packages` (expected `No issues found!`)

```bash
git add packages/token_manager/lib packages/token_manager/test
git commit -m "feat(token_manager): refresh close-to-expiry tokens in the background

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `refreshIfNeeded` in the engine and `TokenManager`

**Files:**
- Modify: `packages/token_manager/lib/src/engine/ahead_refresh.dart`
- Modify: `packages/token_manager/lib/src/engine/token_engine.dart`
- Modify: `packages/token_manager/lib/src/token_manager.dart`
- Create: `packages/token_manager/test/engine/token_engine_if_needed_test.dart`
- Modify: `packages/token_manager/test/token_manager_test.dart`

**Interfaces:**
- Consumes (Tasks 1-2): `AheadRefresh._flight` (private, same class), `RefreshPolicy.isExpiring(T, Duration)`, `RefreshPolicy.window`, `NotAuthenticated`.
- Produces:
  - `Future<void> AheadRefresh.ifNeeded(T? tokens, Duration? within)`.
  - `Future<void> TokenEngine.refreshIfNeeded({Duration? within})`.
  - `Future<void> TokenManager.refreshIfNeeded({Duration? within})` (public API).

- [ ] **Step 1: Write the failing engine tests**

Create `packages/token_manager/test/engine/token_engine_if_needed_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/refresh_failure.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';

void main() {
  const ahead = Duration(minutes: 5);
  // Between the 30 second skew and the 5 minute window.
  const inWindow = Duration(minutes: 3);
  // Assigned in setUp, which runs before every test.
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('completes without a refresh when enough time is left', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(hours: 1)));

    await engine.refreshIfNeeded();

    expect(fixture.refresher.callCount, 0);
  });

  test('completes without a session and without calling the refresher', () async {
    final engine = fixture.engine();

    await engine.refreshIfNeeded();

    expect(fixture.refresher.callCount, 0);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('completes without a refresher', () async {
    final engine = fixture.engine(withRefresher: false);
    await engine.setTokens(fixture.tokens(const Duration(seconds: 5)));

    await engine.refreshIfNeeded();

    expect(fixture.refresher.callCount, 0);
  });

  test('awaits the refresh of tokens inside the skew', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    var done = false;

    final pending = engine.refreshIfNeeded().then((_) => done = true);
    await settle();
    expect(done, isFalse);
    fixture.refresher.complete(fresh);
    await pending;

    expect(fixture.store.stored, same(fresh));
    expect(engine.state.tokensOrNull, same(fresh));
    expect(fixture.refresher.callCount, 1);
  });

  test('loads the stored tokens first', () async {
    final stored = fixture.tokens(const Duration(seconds: 10));
    fixture.store.stored = stored;
    final engine = fixture.engine();

    final pending = engine.refreshIfNeeded();
    await settle();

    expect(fixture.refresher.callCount, 1);
    expect(fixture.refresher.requested.single, same(stored));
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await pending;
  });

  test('joins the refresh in flight', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final blocking = engine.validToken();
    final explicit = engine.refreshIfNeeded();
    await settle();
    fixture.refresher.complete(fresh);

    expect(await blocking, same(fresh));
    await explicit;
    expect(fixture.refresher.callCount, 1);
  });

  test('joins a background refresh', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    await engine.validToken();

    final explicit = engine.refreshIfNeeded();
    await settle();
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await explicit;

    expect(fixture.refresher.callCount, 1);
  });

  test('throws InvalidGrant and ends the session', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));

    final failed = expectLater(
      engine.refreshIfNeeded(),
      throwsA(isA<InvalidGrant>()),
    );
    await settle();
    fixture.refresher.fail(const InvalidGrant());
    await failed;

    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('throws Transient and keeps the session', () async {
    final engine = fixture.engine();
    final current = fixture.tokens(const Duration(seconds: 10));
    await engine.setTokens(current);

    final failed = expectLater(
      engine.refreshIfNeeded(),
      throwsA(isA<Transient>()),
    );
    await settle();
    fixture.refresher.fail(const Transient('offline'));
    await failed;

    expect(engine.state, isA<Authenticated<TokenSet>>());
    expect(engine.state.tokensOrNull, same(current));
  });

  test('completes when a logout supersedes the refresh', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));

    final pending = engine.refreshIfNeeded();
    await settle();
    await engine.logout();
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await pending;

    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('within larger than the default refreshes earlier', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(minutes: 5)));

    await engine.refreshIfNeeded();
    expect(fixture.refresher.callCount, 0);

    final pending = engine.refreshIfNeeded(within: const Duration(minutes: 10));
    await settle();
    expect(fixture.refresher.callCount, 1);
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await pending;
  });

  test('within defaults to refreshAhead when it is set', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));

    final pending = engine.refreshIfNeeded();
    await settle();

    expect(fixture.refresher.callCount, 1);
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await pending;
  });

  test('within defaults to the skew without refreshAhead', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(inWindow));

    await engine.refreshIfNeeded();

    expect(fixture.refresher.callCount, 0);
  });

  test('refreshes tokens a failed background attempt left behind', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    await engine.validToken();
    fixture.refresher.fail(const Transient('offline'));
    await settle();
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final explicit = engine.refreshIfNeeded();
    await settle();
    fixture.refresher.complete(fresh, call: 1);
    await explicit;

    expect(fixture.refresher.callCount, 2);
    expect(engine.state.tokensOrNull, same(fresh));
  });
}
```

(`dart format` in Step 7 wraps the two test names that exceed 80 columns.)

- [ ] **Step 2: Write the failing manager tests**

Append to `packages/token_manager/test/token_manager_test.dart` before the closing `}` of `main`:

```dart
  test('refreshIfNeeded refreshes tokens that expire within the window', () async {
    await manager.setTokens(tokens(const Duration(minutes: 3)));

    final pending = manager.refreshIfNeeded(within: const Duration(minutes: 5));
    await settle();
    refresher.complete(tokens(const Duration(hours: 1), access: 'b'));
    await pending;

    expect((await manager.current())?.accessToken, 'b');
  });

  test('refreshIfNeeded does nothing when signed out', () async {
    await manager.refreshIfNeeded();

    expect(refresher.callCount, 0);
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/engine/token_engine_if_needed_test.dart`
Expected: compile error, `refreshIfNeeded` is not defined for `TokenEngine`.

- [ ] **Step 4: Implement `AheadRefresh.ifNeeded`**

In `packages/token_manager/lib/src/engine/ahead_refresh.dart` add `import '../not_authenticated.dart';` (sorted before `../token_refresher.dart`) and this method after `startAhead`'s helper `_guardAgainstLoop`:

```dart
  /// Refreshes [tokens] when they expire within [within] and waits for it.
  ///
  /// [within] defaults to the refresh-ahead window, or the skew without one.
  /// Does nothing without tokens or a refresher. It starts a refresh or joins
  /// the one in flight and throws what that refresh throws, except that a
  /// logout which superseded it ends the wait quietly.
  Future<void> ifNeeded(T? tokens, Duration? within) async {
    final refresher = _refresher;
    if (tokens == null ||
        refresher == null ||
        !_policy.isExpiring(tokens, within ?? _policy.window)) {
      return;
    }
    try {
      await _flight(refresher, tokens);
    } on NotAuthenticated {
      // A logout superseded the refresh: there is nothing left to refresh.
    }
  }
```

- [ ] **Step 5: Implement the engine and manager methods**

In `packages/token_manager/lib/src/engine/token_engine.dart` add after `validToken`:

```dart
  /// Refreshes the tokens when less than [within] is left, and waits for it.
  ///
  /// [within] defaults to the refresh-ahead window, or to the skew without
  /// one. Completes normally without tokens, without a refresher or when
  /// enough time is left; otherwise it throws what the refresh throws.
  Future<void> refreshIfNeeded({Duration? within}) async {
    await _loader.load();
    await _refresh.ifNeeded(state.tokensOrNull, within);
  }
```

In `packages/token_manager/lib/src/token_manager.dart` add after `validToken`:

```dart
  /// Refreshes the tokens when less than [within] is left before they expire.
  ///
  /// Use it at a moment you choose, such as start-up or app resume, to have
  /// fresh tokens before the first request. [within] defaults to the
  /// `refreshAhead` given to [TokenManager.create], or to its `skew` when none
  /// was given; pass a larger value, for example `Duration(minutes: 10)`, to
  /// refresh earlier. Completes normally without tokens, without a refresher
  /// and when enough time is left. A refresh that is needed is awaited through
  /// the single flight and its `InvalidGrant` or `Transient` is thrown to the
  /// caller.
  Future<void> refreshIfNeeded({Duration? within}) =>
      _engine.refreshIfNeeded(within: within);
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/engine/token_engine_if_needed_test.dart`
Expected: all pass.

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/token_manager_test.dart`
Expected: all pass.

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
Expected: all pass, `size_limits_test` included. If it complains about `token_engine.dart`, recount the engine's members (the budget is 15, see File Structure) rather than adding an allowlist entry.

- [ ] **Step 7: Format, analyze, commit**

Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart format packages` (twice; second run 0 changed)
Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart analyze packages` (expected `No issues found!`)

```bash
git add packages/token_manager/lib packages/token_manager/test
git commit -m "feat(token_manager): add refreshIfNeeded

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Documentation

Replaces the "no background timer" wording everywhere. Do not link to the new recipe yet (Task 5 adds the page and every link to it).

**Files:**
- Modify: `packages/token_manager/doc/concepts.md`, `doc/refreshing.md`, `doc/getting_started.md`, `doc/migration.md`, `doc/recipes/session_expiry.md`, `README.md`, `lib/src/token_manager.dart` (class doc)
- Test: `packages/docs_check` (links and README checks)

**Interfaces:**
- Consumes: the public API from Tasks 1-3 (`refreshAhead`, `refreshIfNeeded`).
- Produces: the heading `Refreshing before expiry` in `doc/refreshing.md` and in `README.md` (Task 5 links to the README anchor `#refreshing-before-expiry` and to `refreshing.md`).

- [ ] **Step 1: `doc/concepts.md`**

Replace the section from `## Why no background timer` up to (not including) `## Where to go next` with:

```markdown
## Refreshing before expiry

There is still no background timer. A timer needs a lifecycle (when to start,
pause on app suspend, stop on logout), keeps the isolate busy, and refreshes
tokens nobody is about to use. Two on-demand tools cover the same need:

- `refreshAhead` makes `validToken` return a still-valid token at once and
  start the refresh in the background when the token is close to expiry. The
  call that would have paid for the refresh does not wait.
- `refreshIfNeeded()` refreshes at a moment the app chooses, such as start-up
  or return from the background, and waits for the result.

Both use the single flight: a background refresh and a caller that needs a
refresh share one future. Without either, the first call after the margin pays
one round trip and every concurrent caller shares it. The windows and the
failure rules are in [Refreshing](refreshing.md).

```

In the same file, change the closing list item `- [Refreshing](refreshing.md) — expiry, skew and failure types.` to `- [Refreshing](refreshing.md) — expiry, skew, refreshing ahead and failure types.`

- [ ] **Step 2: `doc/refreshing.md`**

After the paragraph that ends `a token that would expire mid-flight is refreshed first.` (end of the "TokenInfo and skew" section) and before `## InvalidGrant vs Transient`, insert:

````markdown
## Refreshing before expiry

`skew` is the margin below which `validToken` waits for a refresh.
`refreshAhead` is a second, larger margin: tokens that are valid but expire
within it are returned at once and refreshed in the background.

| Time left | Default | With `refreshAhead` |
|---|---|---|
| more than `refreshAhead` | return | return |
| between `skew` and `refreshAhead` | return | return, and refresh in the background |
| less than `skew` | refresh and wait | refresh and wait |

```dart
import 'package:token_manager/token_manager.dart';

final aheadManager = TokenManager<TokenSet>.create(
  store: InMemoryTokenStore<TokenSet>(),
  refresher: HttpRefresher(),
  info: const TokenSetInfo(),
  skew: const Duration(seconds: 30),
  refreshAhead: const Duration(minutes: 5),
);
```

`refreshAhead` is `null` by default, which turns it off. It must be greater
than `skew`, or `create` throws an `ArgumentError`. Choose it well below the
lifetime of your tokens: a token that is issued already inside the window is
still refreshed ahead once, and the blocking path takes over at `skew`.

The background refresh follows these rules:

- **Single flight.** It is the session's one refresh. A caller that arrives
  during it and needs a refresh (less than `skew` left, or a rejected token)
  awaits it like any other.
- **One attempt per tokens object.** After a failed background attempt the
  manager does not try again for the same tokens, so a failing server is not
  hit by every request. When the tokens reach `skew`, the blocking refresh
  retries as usual.
- **Failures stay quiet.** `Transient`, or any other `Exception`, is dropped:
  the state returns to `Authenticated` and nothing is thrown. `InvalidGrant`
  ends the session as it always does: the store is cleared and `states` emits
  `Unauthenticated`. An `Error` is never caught.
- **Sessions are respected.** `setTokens`, `logout` and `InvalidGrant` discard
  the result of a running background refresh. `dispose` does not: a rotated
  refresh token is not lost. After `dispose` no new background refresh starts.

### refreshIfNeeded

`refreshIfNeeded` refreshes at a moment you choose and waits for it:

```dart
Future<void> onStart(TokenManager<TokenSet> manager) async {
  try {
    await manager.refreshIfNeeded(within: const Duration(minutes: 10));
  } on Transient {
    // Offline at start-up is normal; the next request retries.
  }
}
```

`within` defaults to `refreshAhead`, or to `skew` when it is not set. With no
tokens, no refresher, or enough time left, it completes without calling the
refresher; being signed out is not an error here. When a refresh is needed it
awaits the single flight and throws `InvalidGrant` or `Transient` to the
caller. It never reports a rejected token; that stays in `validToken`.

````

Also in the section "When a refresh runs", after the sentence `Without a `refresher` tokens are never refreshed; without `info` they never\nexpire (a rejected token can still trigger a refresh).` add a new paragraph: `With `refreshAhead` set, `validToken` also starts a background refresh for tokens that are close to expiry; see below.`

- [ ] **Step 3: `doc/getting_started.md`**

After the paragraph `` `validToken` refreshes when `info` says the tokens expire within `skew` `` ... `It throws `NotAuthenticated` when nobody is signed in.` add:

```markdown
To spare the caller that pays for a refresh, pass `refreshAhead` (for example
`Duration(minutes: 5)`) to `create`: tokens that are close to expiry are then
returned at once and refreshed in the background. To refresh at a moment you
choose, such as start-up, call `refreshIfNeeded()`. Neither uses a timer; see
[Refreshing](refreshing.md).
```

Change the last list item to `- [Concepts](concepts.md) — when a refresh happens and why it is single-flight.`

- [ ] **Step 4: `doc/migration.md`**

Replace the first bullet under `## Behaviour changes`:

```markdown
- There is no background proactive refresh any more, in the deprecated API
  too. Refresh happens on `validToken`, `authorize` or a rejected token. If
  you relied on `infoDelegate` for refresh before expiry, you lose it until
  you call `validToken` before each use. Proactive refresh is planned for a
  later release.
```

with:

```markdown
- There is no background timer any more, in the deprecated API too. Refresh
  happens on `validToken`, `authorize` or a rejected token. If you relied on
  `infoDelegate` for refresh before expiry, pass `refreshAhead` to
  `TokenManager.create` (0.2.3 and later) to refresh close-to-expiry tokens in
  the background on the next `validToken`, or call `refreshIfNeeded()` at
  start-up and when the app resumes.
```

- [ ] **Step 5: `doc/recipes/session_expiry.md`**

Replace the bullet:

```markdown
- **Expecting a timer.** Refresh is on demand: a session that dies while the app
  is idle is noticed on the next `validToken` or `authorize`.
```

with:

```markdown
- **Expecting a timer.** There is none: a session that dies while the app is
  idle is noticed on the next `validToken`, `authorize` or `refreshIfNeeded`.
  To check at a moment you choose, such as app resume, call `refreshIfNeeded`.
```

- [ ] **Step 6: `README.md`**

Replace the blockquote

```markdown
> Refresh is on demand. There is no background timer: tokens are refreshed when `validToken`, `authorize`
> or a rejected token asks for it.
```

with

```markdown
> Refresh is on demand: tokens are refreshed when `validToken`, `authorize` or a rejected token asks for it.
> There is no background timer; `refreshAhead` and `refreshIfNeeded` move the refresh off the request path
> (see [Refreshing before expiry](#refreshing-before-expiry)).
```

In the Contents list insert `- [Refreshing before expiry](#refreshing-before-expiry)` after `- [Authorizing calls](#authorizing-calls)`. Insert this section before `## Errors`:

````markdown
## Refreshing before expiry

`validToken` waits for a refresh only when less than `skew` is left. Set `refreshAhead` to refresh earlier,
in the background:

```dart
final manager = TokenManager<TokenSet>.create(
  store: InMemoryTokenStore<TokenSet>(),
  refresher: MyRefresher(),
  info: const TokenSetInfo(),
  refreshAhead: const Duration(minutes: 5), // must be greater than skew
);
```

A call that finds the tokens with less than five minutes left gets them at once and starts the refresh behind
it. A failed background refresh never signs the user out unless the server rejected the refresh token.

`refreshIfNeeded` refreshes at a moment you choose and waits for it, for example at start-up or when the app
returns to the foreground:

```dart
await manager.refreshIfNeeded(within: const Duration(minutes: 10));
```

**[doc/refreshing.md](doc/refreshing.md)** has the windows and the failure rules.

````

In the `Errors` table add nothing. In the `Reference` table change the Refreshing row to `| [Refreshing](doc/refreshing.md) | `TokenRefresher`, `TokenInfo` and skew, refreshing before expiry, failure types |`.

- [ ] **Step 7: Class doc in `lib/src/token_manager.dart`**

Replace

```dart
/// Refresh is on demand: tokens are refreshed when [validToken], [authorize]
/// or a rejected token asks for it, never by a background timer. Concurrent
/// callers share one refresh.
```

with

```dart
/// Refresh is on demand: tokens are refreshed when [validToken], [authorize],
/// [refreshIfNeeded] or a rejected token asks for it, and, when `refreshAhead`
/// is set, in the background just before they expire. There is no timer.
/// Concurrent callers share one refresh.
```

- [ ] **Step 8: Verify**

Run: `cd packages/docs_check && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
Expected: all pass (README block checks, link and anchor checks, banned wording).

Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart format packages` (twice; second run 0 changed)
Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart analyze packages` (expected `No issues found!`)

- [ ] **Step 9: Commit**

```bash
git add packages/token_manager/doc packages/token_manager/README.md packages/token_manager/lib/src/token_manager.dart
git commit -m "docs(token_manager): describe refreshAhead and refreshIfNeeded instead of the missing timer

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Recipe "Refresh on app resume"

**Files:**
- Create: `packages/token_manager/example/recipes/refresh_on_resume.dart`
- Create: `packages/token_manager/test/recipes/refresh_on_resume_test.dart`
- Create: `packages/token_manager/doc/recipes/refresh_on_resume.md`
- Modify: `packages/token_manager/dartdoc_options.yaml`, `packages/token_manager/README.md` (Recipes list), `docs/recipes.md`, `llms.txt`

**Interfaces:**
- Consumes: `TokenManager.create(refreshAhead:)`, `refreshIfNeeded({within})`, `Transient`, `InvalidGrant`, `RefreshFailure`, `Clock`, `test/helpers/fake_clock.dart`.
- Produces: `ResumeRefresh` (`const ResumeRefresh(TokenManager<TokenSet>)`, `Future<void> onResumed()`, `static const Duration window`) and `StandInRefresher` (`StandInRefresher({Clock clock, RefreshFailure? failure})`, `int calls`), both in `example/recipes/refresh_on_resume.dart`.

- [ ] **Step 1: Write the failing recipe test**

Create `packages/token_manager/test/recipes/refresh_on_resume_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/refresh_on_resume.dart'
    show ResumeRefresh, StandInRefresher;
import '../helpers/fake_clock.dart';

void main() {
  final clock = FakeClock(DateTime.utc(2026));

  TokenSet tokensExpiringIn(Duration life) => TokenSet(
    accessToken: 'access-0',
    refreshToken: 'refresh-0',
    expiresAt: clock.now().add(life),
  );

  TokenManager<TokenSet> managerWith(StandInRefresher refresher) {
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(),
      refresher: refresher,
      info: const TokenSetInfo(),
      refreshAhead: const Duration(minutes: 5),
      clock: clock,
    );
    addTearDown(manager.dispose);
    return manager;
  }

  test('tokens with less than ten minutes left are refreshed on resume', () async {
    final refresher = StandInRefresher(clock: clock);
    final manager = managerWith(refresher);
    await manager.setTokens(tokensExpiringIn(const Duration(minutes: 8)));

    await ResumeRefresh(manager).onResumed();

    expect(refresher.calls, 1);
    expect((await manager.current())?.accessToken, 'access-1');
  });

  test('tokens with plenty of time left are not refreshed', () async {
    final refresher = StandInRefresher(clock: clock);
    final manager = managerWith(refresher);
    await manager.setTokens(tokensExpiringIn(const Duration(hours: 1)));

    await ResumeRefresh(manager).onResumed();

    expect(refresher.calls, 0);
    expect((await manager.current())?.accessToken, 'access-0');
  });

  test('a signed-out app does nothing on resume', () async {
    final refresher = StandInRefresher(clock: clock);
    final manager = managerWith(refresher);

    await ResumeRefresh(manager).onResumed();

    expect(refresher.calls, 0);
    expect(await manager.current(), isNull);
  });

  test('an offline resume keeps the session and does not throw', () async {
    final refresher = StandInRefresher(
      clock: clock,
      failure: const Transient('offline'),
    );
    final manager = managerWith(refresher);
    await manager.setTokens(tokensExpiringIn(const Duration(minutes: 8)));

    await ResumeRefresh(manager).onResumed();

    expect(refresher.calls, 1);
    expect((await manager.current())?.accessToken, 'access-0');
  });

  test('a dead refresh token signs out on resume without throwing', () async {
    final refresher = StandInRefresher(
      clock: clock,
      failure: const InvalidGrant(),
    );
    final manager = managerWith(refresher);
    await manager.setTokens(tokensExpiringIn(const Duration(minutes: 8)));

    await ResumeRefresh(manager).onResumed();

    expect(await manager.current(), isNull);
  });

  test('two resumes at once share one refresh', () async {
    final refresher = StandInRefresher(clock: clock);
    final manager = managerWith(refresher);
    await manager.setTokens(tokensExpiringIn(const Duration(minutes: 8)));
    final resume = ResumeRefresh(manager);

    await Future.wait([resume.onResumed(), resume.onResumed()]);

    expect(refresher.calls, 1);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/recipes/refresh_on_resume_test.dart`
Expected: compile error, the recipe file does not exist.

- [ ] **Step 3: Write the recipe code**

Create `packages/token_manager/example/recipes/refresh_on_resume.dart`:

```dart
import 'dart:io';

import 'package:token_manager/token_manager.dart';

/// Refreshes the session when the app comes back to the foreground, so the
/// first request after a long pause does not wait for a refresh.
final class ResumeRefresh {
  /// Creates the helper over [_manager].
  const ResumeRefresh(this._manager);

  /// The margin used on resume: tokens that expire sooner are refreshed.
  static const Duration window = Duration(minutes: 10);

  final TokenManager<TokenSet> _manager;

  /// Call this from the app's lifecycle callback when it resumes.
  ///
  /// Tokens with less than [window] left are refreshed now. A network failure
  /// is ignored: the next request retries. A dead refresh token signs the
  /// session out, which a `states` listener already reports.
  Future<void> onResumed() async {
    try {
      await _manager.refreshIfNeeded(within: window);
    } on Transient {
      // Offline on resume is normal; the next request retries.
    } on InvalidGrant {
      // The session ended; the app reacts to `states`, not to this call.
    }
  }
}

// ---- Stand-in for the token endpoint, so this file runs without a server.

/// A refresher that counts its calls and can be told to fail.
final class StandInRefresher implements TokenRefresher<TokenSet> {
  /// Creates the refresher; with [failure] set, every call throws it.
  StandInRefresher({this.clock = const Clock(), this.failure});

  /// The clock that the lifetime of the new tokens is counted from.
  final Clock clock;

  /// What every call throws, or `null` to succeed.
  final RefreshFailure? failure;

  /// How many times [refresh] was called.
  int calls = 0;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    calls++;
    if (failure case final error?) {
      throw error;
    }
    return TokenSet(
      accessToken: 'access-$calls',
      refreshToken: 'refresh-$calls',
      expiresAt: clock.now().add(const Duration(hours: 1)),
    );
  }
}

Future<void> main() async {
  final refresher = StandInRefresher();
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: refresher,
    info: const TokenSetInfo(),
    refreshAhead: const Duration(minutes: 5),
  );
  // Eight minutes left: outside the five minute refreshAhead window, so
  // validToken would not refresh, but inside the ten minute resume window.
  await manager.setTokens(
    TokenSet(
      accessToken: 'access-0',
      refreshToken: 'refresh-0',
      expiresAt: DateTime.now().add(const Duration(minutes: 8)),
    ),
  );

  await ResumeRefresh(manager).onResumed();

  final tokens = await manager.current();
  stdout.writeln('Refreshed ${refresher.calls} time: ${tokens?.accessToken}');
  await manager.dispose();
}
```

- [ ] **Step 4: Run the recipe test and the example**

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test test/recipes/refresh_on_resume_test.dart`
Expected: all pass.

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart run example/recipes/refresh_on_resume.dart`
Expected output: `Refreshed 1 time: access-1`

- [ ] **Step 5: Write the recipe page**

Create `packages/token_manager/doc/recipes/refresh_on_resume.md`. The text is below; the Dart block must be the **exact content** of `example/recipes/refresh_on_resume.dart` (run `cat packages/token_manager/example/recipes/refresh_on_resume.dart` and paste it between the fences; `docs_check` compares them byte for byte, the trailing newline aside). Keep the marker line directly above the fence.

````markdown
# Recipe: refresh the session on app resume

Make sure the tokens are fresh when the app returns from the background, so
the first request after a long pause does not wait for a refresh.

## The code

`ResumeRefresh` is called from your lifecycle callback. In Flutter that is
`didChangeAppLifecycleState` when the state is `AppLifecycleState.resumed`.
`StandInRefresher` stands in for the token endpoint.

<!-- include: example/recipes/refresh_on_resume.dart -->
```dart
(the whole content of example/recipes/refresh_on_resume.dart goes here)
```

Run it with `dart run example/recipes/refresh_on_resume.dart`. The test
`test/recipes/refresh_on_resume_test.dart` checks every behaviour below.

## What you get

- Tokens with less than ten minutes left are refreshed on resume, and the new
  tokens are stored. The ten minute window is larger than the five minute
  `refreshAhead` of the example, which acts only when a request asks for a
  token.
- Tokens with more time left are not touched, and the refresher is not called.
- A signed-out app does nothing: being signed out is not an error for
  `refreshIfNeeded`.
- An offline resume (`Transient`) keeps the session and does not throw; the
  next request retries.
- A dead refresh token (`InvalidGrant`) signs the session out and `onResumed`
  does not throw; a `states` listener, as in the session-expiry recipe,
  reports it.
- Two resumes at once share one refresh.

## Common mistakes

- **Waiting for it before the first frame.** `onResumed` can wait on the
  network. Start it without blocking the UI; the next request refreshes the
  tokens anyway if it has not finished.
- **Picking a window longer than the token lifetime.** Every resume then
  refreshes. Use a window of a few minutes, well below the lifetime.
- **Setting `refreshAhead` to `skew` or less.** `create` throws an
  `ArgumentError`; `refreshAhead` must be greater than `skew`.
- **Expecting a timer.** `refreshAhead` acts when a request asks for a token
  and `refreshIfNeeded` when you call it. A suspended app refreshes nothing,
  which is why the resume callback calls it.
- **Letting `Transient` escape.** `refreshIfNeeded` throws it to the caller;
  catch it where a failed refresh should not stop the app.

## See also

- [Refreshing before expiry](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/refreshing.md)
- [Send the user to sign-in when the session ends](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/recipes/session_expiry.md)
````

In the real file replace the parenthesised line inside the Dart fence by the file content; it must not stay as a placeholder.

- [ ] **Step 6: Register the recipe**

`packages/token_manager/dartdoc_options.yaml`: add after `recipe-session-expiry`:

```yaml
    recipe-refresh-on-resume:
      markdown: doc/recipes/refresh_on_resume.md
      displayName: "Recipe: refresh the session on app resume"
```

and `    - recipe-refresh-on-resume` in `categoryOrder` after `    - recipe-session-expiry`.

`packages/token_manager/README.md`, Recipes list: add after the session-expiry line

```markdown
- [Refresh the session on app resume](doc/recipes/refresh_on_resume.md)
```

and in the README section "Refreshing before expiry" (added in Task 4) replace the line `**[doc/refreshing.md](doc/refreshing.md)** has the windows and the failure rules.` with `**[doc/refreshing.md](doc/refreshing.md)** has the windows and the failure rules; [Refresh the session on app resume](doc/recipes/refresh_on_resume.md) is a complete recipe.`

`docs/recipes.md`: in the task table, after the `show the sign-in screen when the session ends` row insert

```markdown
| make sure the tokens are fresh when the app resumes | [Refresh the session on app resume](../packages/token_manager/doc/recipes/refresh_on_resume.md) |
```

and in the "By package" row of `token_manager` change the recipe list to `sign in, secure storage, session expiry, refresh on resume, testing`.

`llms.txt`: after the "Send the user to sign-in" line insert

```markdown
- [Refresh the session on app resume](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/recipes/refresh_on_resume.md): refreshIfNeeded from the lifecycle callback, with refreshAhead.
```

- [ ] **Step 7: Verify**

Run: `cd packages/docs_check && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
Expected: all pass. A failure `differs from the file; paste the file again` means the Dart block differs from the file; paste it again. A failure naming banned wording means a phrase from the Global Constraints list is in the page.

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
Expected: all pass.

Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart format packages` (twice; second run 0 changed)
Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart analyze packages` (expected `No issues found!`)

If `dart format` reformats the example, paste the formatted file into the page again and rerun the docs_check step.

- [ ] **Step 8: Commit**

```bash
git add packages/token_manager/example packages/token_manager/test/recipes packages/token_manager/doc packages/token_manager/dartdoc_options.yaml packages/token_manager/README.md docs/recipes.md llms.txt
git commit -m "docs(token_manager): add the refresh on app resume recipe

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Version 0.2.3 and CHANGELOG

**Files:**
- Modify: `packages/token_manager/pubspec.yaml`
- Modify: `packages/token_manager/CHANGELOG.md`

**Interfaces:**
- Consumes: the finished feature from Tasks 1-5.
- Produces: the release commit; the tag `token_manager-v0.2.3` is pushed by the user after merge (see `docs/releasing.md`), not by this plan.

- [ ] **Step 1: Bump the version**

In `packages/token_manager/pubspec.yaml` change `version: 0.2.2` to `version: 0.2.3`. Do not touch any adapter `pubspec.yaml`: their `^0.2.0` constraint resolves 0.2.3.

- [ ] **Step 2: Add the CHANGELOG entry**

In `packages/token_manager/CHANGELOG.md` insert above `## 0.2.2`:

```markdown
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
- Docs: a recipe, "Refresh the session on app resume", and a rewritten
  "Refreshing before expiry" section. There is still no background timer.
- The transport adapters need no change: they get refresh ahead through
  `validToken`.
```

- [ ] **Step 3: Full verification, one package at a time**

Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart pub get`
Expected: resolves (the adapters' `^0.2.0` constraints accept 0.2.3 through the workspace).

Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart format packages` (twice; second run 0 changed)
Run: `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart analyze packages` (expected `No issues found!`)

Then, one after the other, each expected to pass:
`cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
`cd packages/docs_check && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
`cd packages/token_manager_dio && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
`cd packages/token_manager_http && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
`cd packages/token_manager_grpc && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`
`cd packages/token_manager_gql && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart test`

Run: `cd packages/token_manager && systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart pub publish --dry-run`
Expected: `Package has 0 warnings.`

- [ ] **Step 4: Check the engine budget and the diff scope**

Run: `grep -c "" packages/token_manager/lib/src/engine/ahead_refresh.dart packages/token_manager/lib/src/engine/token_engine.dart`
Expected: both well under 300 lines.

Run: `git diff --stat main -- packages/token_manager_dio packages/token_manager_http packages/token_manager_grpc packages/token_manager_gql`
Expected: empty (no adapter changed).

Count the members of `TokenEngine` (constructor, 4 fields `_store`, `_session`, `_refresh`, `_loader`, `states`, `state`, `current`, `validToken`, `refreshIfNeeded`, `pendingRefresh`, `setTokens`, `logout`, `dispose`, `_clear`): 15.

- [ ] **Step 5: Commit**

```bash
git add packages/token_manager/pubspec.yaml packages/token_manager/CHANGELOG.md
git commit -m "build(token_manager): release 0.2.3

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage.**
- Windows table and `refreshAhead > skew` validation: Task 1 (policy, `create`), tests in `refresh_policy_test.dart` and `token_manager_test.dart`.
- A, decision order (no tokens / no refresher, then blocking, then ahead): Task 2, `validToken`. Same flight, 10 concurrent callers, joining at `skew`: `token_engine_ahead_test.dart`. One attempt per tokens, retry at `skew`: failure test file. Failures (`Transient`, other `Exception`, `InvalidGrant`, `Error` not caught, no unhandled error): failure test file via `UncaughtErrors`. Epoch (`logout`, `setTokens`) and `dispose` (persisted, no new refresh): failure test file. The bare `unawaited(validToken())` is avoided: `startAhead` owns the handling (`unawaited(_flight(...).then(...).catchError(..., test: Exception))`).
- B, `refreshIfNeeded`: Task 3, all bullets (defaults of `within`, no tokens / no refresher / enough time, single flight start-or-join, `InvalidGrant`/`Transient` thrown, larger `within`, never reports a rejected token because it has no `rejected`).
- Engine and policy (`isExpiring`, `AheadRefresh` holding the attempt memory and ahead decision, engine member count): Tasks 1-3 and File Structure. Deviation recorded: the spec's engine method `refreshInBackground` is `AheadRefresh.startAhead`, to keep `TokenEngine` at 15 members. Addition not in the spec: the loop guard (`_guardAgainstLoop`), pinned by a test, for Review Focus item 1.
- Versioning 0.2.3, no adapter change: Task 6 (diff-stat check).
- Documentation list (concepts, refreshing, README, getting_started, session_expiry, migration, class doc, new recipe, CHANGELOG, llms.txt, recipe index): Tasks 4-6; `dartdoc_options.yaml` is added because every recipe has a dartdoc category.
- Testing list and `size_limits_test`/analyze: each task's verification steps.

**Placeholder scan.** The only intentional indirection is the recipe page's Dart block, which must be the on-disk file (Step 5 of Task 5 says how, and `docs_check` enforces equality); the parenthesised line there is called out as something to replace. No TBD/TODO.

**Type consistency.** `RefreshPolicy({skew, clock, refreshAhead, info})`, `isExpiring`, `needsAheadRefresh`, `window`; `TokenEngine({store, policy, refresher})`; `AheadRefresh({session, store, policy, refresher})` with `dueFlight`, `startAhead`, `ifNeeded`; `EngineFixture.engine({withRefresher, refreshAhead})`; `TokenManager.create(refreshAhead:)` and `refreshIfNeeded({within})`; `UncaughtErrors().during`; `Session.isClosed`; `ResumeRefresh.onResumed`/`window`, `StandInRefresher({clock, failure})`/`calls` are used with the same names in every task.
