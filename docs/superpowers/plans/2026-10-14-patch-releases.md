# Patch Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up `token_manager` and `token_manager_http` (class size, docs, tests) and prepare patch releases (0.2.1 / 0.1.1) without any public API or default-behaviour change.

**Architecture:** Private collaborators are extracted from over-sized classes, each in its own file with its own tests; documentation gaps are closed; versions are bumped last, one commit per package.

**Tech Stack:** Dart 3.10 pub workspace, `package:test`, `package:http`, `dart doc`.

**Spec:** `docs/superpowers/specs/2026-10-14-token-manager-redesign-design.md`; rules in `CLAUDE.md` and `docs/releasing.md`.

## Global Constraints

- PATCH only (pre-1.0): no new or changed public API, no changed default behaviour. Anything that would need a minor bump is not done; it is recorded as "needs minor".
- Existing tests stay green and unmodified, except a test that only referenced a moved private detail.
- Limits: lib file 300 lines, test file 500, method 40, parameters 5, nesting 3, class about 15 members. `test/quality/size_limits_test.dart` allowlists must not gain entries.
- One public class per file; no `utils`/`helpers`/`common` in `lib/`; no `part`; no top-level functions; no `!`, no `dynamic`; `catch` always has `on`; `///` docs, one summary sentence.
- Commits: Conventional Commits with package scope, trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; a refactor is its own commit. Do not push, merge, tag or publish.
- Gates per task: `dart format packages` (second run changes 0 files), `dart analyze packages` ("No issues found!"), `dart test` in the touched package.

## Review Focus

- TokenEngine: a refresh that finishes after `setTokens`/`logout` is discarded (epoch), and one that finishes after `dispose` is still persisted but emits nothing.
- TokenEngine: concurrent `validToken` callers share one flight; a `rejected` token that is no longer current does not trigger a second refresh.
- TokenEngine: a failed `store.write` after a refresh keeps the refreshed tokens in memory; a failed `store.delete` on `InvalidGrant` still ends the session.
- TokenEngine: a failed first read is retried by the next `current()`/`validToken()`, and `setTokens`/`logout` proceed after a failed read.
- HttpTokenClient: the caller's request never carries the token header (also multipart and streamed); `close` twice closes the inner client once.

---

### Task 1: CLAUDE.md adapter list

**Files:** Modify `CLAUDE.md` ("Where things are").

- [ ] Read `packages/token_manager_gql/README.md` and `packages/token_manager_http/README.md`; add two bullets after the dio/grpc one (or extend it) with accurate one-line descriptions: `token_manager_gql` (a `gql_link` `Link` plus WebSocket auth callbacks) and `token_manager_http` (a `package:http` `Client` wrapper). Keep the "depend only on the core and their transport" statement true for all four.
- [ ] Commit: `docs: list the gql and http adapters in CLAUDE.md`.

### Task 2: TokenEngine, pure seams (policy, queue, loader)

**Files:** Modify `packages/token_manager/lib/src/engine/token_engine.dart`; create under `lib/src/engine/`: `refresh_policy.dart`, `serial_queue.dart`, `stored_tokens_loader.dart` (names may change if a better one fits); tests under `test/engine/` with matching names.

Baseline: 37 members (10 fields, 3 getters, 23 methods). Seams:

- `RefreshPolicy<T>` (final class, `skew`, `clock`, `info`): `bool needsRefresh(T tokens, T? rejected)` = `identical(tokens, rejected) || isExpiring`. Moves `_needsRefresh`, `_isExpiring`, three fields. Unit-test: rejected identical, rejected different, no info, expiring inside skew, exactly at skew boundary, not expiring.
- `SerialQueue` (final class): `Future<R> run<R>(Future<R> Function() action)`, the `_tail` chain from `_exclusive` (an action's failure must not block the next one). Unit-test: order, non-overlap, error isolation, result/error propagation.
- `StoredTokensLoader<T>`: `_loading`, `_load`, `_loadOnce`, `_markLoaded`, `_loadUnlessBroken`. It needs the store, a way to read the current epoch, and a callback for a loaded value; keep the `epoch == _epoch` guard and "failed read is not cached" semantics exactly. Unit-test with `test/helpers/fake_token_store.dart`: loads once for concurrent callers, failed read is retried, `markLoaded` suppresses a later read, epoch change drops the loaded value, `loadUnlessBroken` swallows an `Exception`.

- [ ] Extract one seam at a time (test first for the new class, then wire the engine), running the whole core `dart test` after each.
- [ ] If a seam cannot be extracted without changing behaviour or a test, stop there and report why.
- [ ] Gates; `dart test` in `packages/token_manager` unchanged-green (including `test/quality`).
- [ ] Commit (own commit per seam is fine): `refactor(token_manager): extract <X> from TokenEngine`.

### Task 3: TokenEngine, refresh pipeline (only if clean)

**Files:** as Task 2; candidates `session.dart` (epoch + `ReplayValue` states + queue + `startNewSession` + `emit`) and `refresh_attempt.dart` (`_refresh`, `_attempt`, `_supersededOrThrow`, `_endSession`, `_commit`, `_restore`, `_supersededBy`).

- [ ] Re-count TokenEngine members after Task 2. If it is above about 20, extract the refresh pipeline into a single-use `RefreshAttempt<T>` that talks to the engine through a narrow surface (epoch check, emit, current state, store, queue, new-session). The flight slot (`_flight`, `_forgetWhenDone`, `pendingRefresh`) may move with it or stay.
- [ ] The result must keep: single-flight, epoch discard, compare-and-skip on the rejected token, persistence after `dispose`, `Refreshing` never stuck on an `Error`. The existing `token_engine_*_test.dart` files must pass unmodified; add focused tests for any new class that has its own behaviour.
- [ ] If no clean seam exists, change nothing and report the member count reached.
- [ ] Gates; commit `refactor(token_manager): extract the refresh attempt from TokenEngine`.

### Task 4: HttpTokenClient defaults collaborator

**Files:** Modify `packages/token_manager_http/lib/src/http_token_client.dart`; create `lib/src/client_defaults.dart` (internal, not exported from `lib/token_manager_http.dart`); test `test/client_defaults_test.dart`.

- [ ] Move `_bearer`, `_isUnauthorized`, `_authorizesAll`, `_unauthorized` and the `headers == null && T != TokenSet` check into a `ClientDefaults` class (static members with the constants inside it). The client keeps its public constructor signature and every behaviour (ArgumentError for non-`TokenSet` without `headers`, StateError text unchanged).
- [ ] Target: `HttpTokenClient` about 15 members. Unit-test the defaults (Bearer header for `TokenSet`, StateError for another type, 401 only, authorizes all).
- [ ] Gates; commit `refactor(token_manager_http): move the client defaults into their own class`.

### Task 5: token_manager_http deferred test items

**Files:** `packages/token_manager_http/test/**` (including `test/helpers/` `RecordingClient`).

- [ ] (a) Test: a `MultipartRequest` sent through the client leaves the caller's request headers free of the token header (the inner client receives it).
- [ ] (b) Test: after `close()` a request that `shouldAuthorize` declines still throws `ClientException` (the closed guard runs before the bypass) and the inner client is not used.
- [ ] (c) Fix `RecordingClient.unreadBodies` to decrement when the body stream is done rather than when it is listened to; existing tests that relied on the old timing are adjusted only if they referenced it.
- [ ] (d) Where `RejectedResponse` rebuilds a response, add an assertion that `isRedirect` is preserved; if the production code does not preserve it, do NOT fix it: report it as a finding.
- [ ] Gates; commit `test(token_manager_http): <what>` (one or several).

### Task 6: token_manager_http docs wording

**Files:** `packages/token_manager_http/lib/src/http_token_client.dart` (doc comment near line 13), `doc/getting_started.md` (lines 36-38), `doc/replay.md` (table), `CHANGELOG.md` is left to Task 10.

- [ ] Make the wording exact: tokens are attached to every request that passes `shouldAuthorize`; a request that fails `shouldAuthorize` is sent unchanged without tokens and never replayed; a request that cannot be replayed (streamed, multipart, other `BaseRequest`) is sent once with tokens and its rejection is returned and reported. Fix the `doc/replay.md` table accordingly.
- [ ] Add to `doc/replay.md`: the rejected 401 body is buffered in memory without a size cap, and the original `content-length` and encoding headers are copied onto the returned response. Verify both against `lib/src/rejected_response.dart` before writing.
- [ ] `dart doc --dry-run` in the package: 0 warnings. Commit `docs(token_manager_http): make the replay wording exact`.

### Task 7: core streams dartdoc category

**Files:** `packages/token_manager/lib/src/**` public types; `packages/token_manager/dartdoc_options.yaml` (the `streams` category already exists).

- [ ] Read `doc/streams.md`; tag the public types it documents (for example the type behind `authorizeStream`, if public) with `/// {@category streams}` as the last doc-comment line, like `refresh_failure.dart`. A type already in a category may carry a second tag if dartdoc accepts it; otherwise tag only types that fit. Tag a public method only if dartdoc supports it. Do not export anything new.
- [ ] `dart doc --dry-run` in `packages/token_manager`: 0 warnings. Commit `docs(token_manager): tag the stream types with the streams category`.

### Task 8: gql clients dartdoc category

**Files:** `packages/token_manager_gql/lib/src/**`, `dartdoc_options.yaml` (the `clients` category exists).

- [ ] Read `doc/clients.md`; tag the public types it covers (`TokenManagerLink`, `SkipAuthorization`, `TokenManagerSocketAuth` as fits) with `/// {@category clients}`.
- [ ] `dart doc --dry-run` in `packages/token_manager_gql`: 0 warnings. Commit `docs(token_manager_gql): tag the client types with the clients category`.

### Task 9: gql current behaviour documented (no code change)

**Files:** `packages/token_manager_gql/doc/auth_failures.md` (and `getting_started.md` if it fits better).

- [ ] Read `lib/src/auth_failure_matcher.dart` and `token_manager_link.dart`. State precisely: (a) a 403 with `UNAUTHENTICATED` is not replayed by default and how to opt in with `AuthFailureMatcher` (show a working snippet that compiles against the real constructor); (b) which exception types reach the caller when the manager fails (`NotAuthenticated`, `InvalidGrant`, `Transient` are thrown as is and are not wrapped in `LinkException`). Verify against the code and existing tests; no code changes.
- [ ] Commit `docs(token_manager_gql): state the 403 and manager-failure behaviour`.
- Record in the final report as "needs minor": 403+UNAUTHENTICATED replay by default; wrapping manager failures in `LinkException`.

### Task 10: Release prep (last)

**Findings fixed before writing:** `curl https://pub.dev/api/packages/<pkg>` returns 200 for all five packages; `token_manager_http` 0.1.0 and `token_manager_gql` 0.1.0 are already published, so both get a patch bump. `docs/releasing.md` and the root README still say "pending"; that is parked, not changed here.

- [ ] For each package run `git diff --name-only main..HEAD -- packages/<pkg>`; only changes under `lib/`, `doc/`, `README`, `CHANGELOG` count (test-only changes do not).
- [ ] Bump `pubspec.yaml` and add a `CHANGELOG.md` entry above the previous one, in the existing format: bare `## x.y.z`, one summary line, bullets, no date, no `**Breaking:**`. Expected: `token_manager` 0.2.1, `token_manager_gql` 0.1.1, `token_manager_http` 0.1.1; `token_manager_dio` and `token_manager_grpc` only if they changed.
- [ ] Update a README install snippet only if it pins the exact patch version (none do today: `^0.1.0` / `^0.2.0` admit the patch).
- [ ] One commit per package: `build(<pkg>): release x.y.z`.
- [ ] `dart pub publish --dry-run` in each bumped package; 0 warnings, or explain each.

### Final gates

- [ ] From the root: `dart format packages` twice (second run 0 changed), `dart analyze packages`, `dart test` in the five packages, size-limit tests green. Whole-branch review by `reviewer` (opus). Remove `.superpowers/` if present.
