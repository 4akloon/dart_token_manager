# token_manager_gql: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the new workspace package `packages/token_manager_gql` (0.1.0): a `gql_link` `Link` named `TokenManagerLink<T>` that attaches `TokenManager` tokens to GraphQL requests and replays a request once after an auth failure, plus a client-agnostic WebSocket helper `TokenManagerSocketAuth<T>`.

**Architecture:** `TokenManagerLink.request` returns the stream of the core's `TokenManager.authorizeStream` (a `StreamController` relay, no `async*`/`await for`), so pause, resume and cancel reach the terminating link and single-flight refresh stays in the core. An auth failure arrives on two channels: an error event (`ServerException.statusCode`) and a normal `Response` whose `errors` carry an auth code. The second channel is turned into a private error event inside the `open` callback (only when `data == null`), because `authorizeStream` replays only on error events, and is turned back into the original `Response` after `authorizeStream` when it is not replayed. Anonymous operations carry a `SkipAuthorization` context entry and bypass the manager. Subscriptions are not handled by the link; `TokenManagerSocketAuth` provides `initialPayload` and `onConnectionLost` callbacks for any WebSocket client.

**Tech Stack:** Dart 3.10+ pub workspace; runtime dependencies `gql_link ^1.0.0`, `gql_exec ^1.0.0`, `token_manager ^0.1.0`; dev dependencies `gql ^1.0.0` (to parse documents in tests and the example) and `test`. No `graphql`, `ferry`, `gql_http_link` or Flutter dependency.

**Spec:** `docs/superpowers/specs/2026-10-14-token-manager-redesign-design.md` (sections 4 and 6, roadmap phase 3 item 4). Research notes behind the rulings below are summarised in this plan; the core API it builds on is `packages/token_manager/lib/src/token_manager.dart` (`authorizeStream`, `validToken`) and `lib/src/engine/relay_stream.dart`.

**Deviations from the spec, already ruled on (do not re-litigate):**

- The package is `token_manager_gql` (spec: `token_manager_gql_link`) and the class is `TokenManagerLink<T>` (spec: `GqlTokenLink<T>`).
- Every operation that goes through the link uses `authorizeStream` (spec: queries and mutations through `authorize`). Subscriptions go through a WebSocket link that ignores HTTP headers, so the link does not handle them; `TokenManagerSocketAuth` covers the socket.
- A response-level rejection is replayed only when `data == null`, because a mutation may already have run.
- Anonymous operations (login, sign-up) skip authorisation through the `SkipAuthorization` context entry instead of failing with `NotAuthenticated`.
- Advised chain: `DedupeLink` → `TokenManagerLink` → `HttpLink`; never combined with graphql_flutter's `AuthLink`.

## Global Constraints

- Branch `feat/token-manager-gql`, created from `main` at `3549079`; never commit to `main`. Run git from the repository root.
- Every commit message uses Conventional Commits with the package scope (`build(token_manager_gql): ...`, `feat(token_manager_gql): ...`, `docs(token_manager_gql): ...`) and ends with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- The package pubspec has `version: 0.1.0`, `resolution: workspace`, `environment: sdk: ^3.10.0`, the same `repository`/`homepage`/`issue_tracker` as the other packages, and **no `publish_to`** (the other packages are publishable and omit it).
- Runtime dependencies are exactly `gql_exec: ^1.0.0`, `gql_link: ^1.0.0`, `token_manager: ^0.1.0`. Never add `graphql`, `graphql_flutter`, `ferry`, `gql_http_link`, `gql_error_link`, `gql_dedupe_link` or Flutter, not even as dev dependencies.
- Dependency wart (verified with `dart pub get`, SDK 3.13.1, 2026-10-14): `gql_exec` 1.1.0 is retracted and `gql_link` 1.1.0 requires `gql_exec ^1.1.0`, so `^1.0.0` resolves to the stable pair `gql_link 1.0.0+1` + `gql_exec 1.0.0+1` (`gql 1.0.1`); `dart pub downgrade` resolves `1.0.0`/`1.0.0`. The `lib/` of `gql_link` 1.0.0+1 and 1.1.0 is identical. Do not raise the floor to `^1.1.0`: it can only resolve to the prerelease `gql_exec 1.1.1-alpha+…`. The pubspec carries a comment saying this.
- The root `pubspec.yaml` workspace list gains `packages/token_manager_gql`, sorted between `token_manager_dio` and `token_manager_grpc`.
- Do **not** modify `.github/workflows/ci.yml` (other adapters change it on other branches). The CI needs are listed in the note at the end of this plan.
- Never consume a stream with `await for` in `lib/`; never write the link as `async*`. Pause, resume and cancel must reach the terminating link.
- Code rules (CLAUDE.md): object-oriented, no top-level functions except `main` in `example/` and tests; no `!`, no `dynamic`; every `catch` has an `on` clause and `Error` is never caught; positive boolean names, no positional `bool` parameters; `///` docs with a one-sentence summary and `[brackets]`; `late` needs a comment; imports inside the package are relative; the barrel uses `export 'src/x.dart' show A;`, one per line, sorted.
- Never add `// ignore:` without a reason; never remove a lint.
- Size limits: lib file 300 lines, test file 500, method 40, parameters 5, nesting 3, about 15 members per class, one public class per file, no `utils`/`helpers`/`common` in `lib/`, no `part`. `test/quality/size_limits_test.dart` is a ratchet with empty allowlists that must stay empty.
- At the end of every task, from the repository root: `dart format packages` changes 0 files on a second run, `dart analyze packages` prints `No issues found!`, and `cd packages/token_manager_gql && dart test` passes.
- Tests ship in the same commit as the code; no network; one behaviour per test, named after the behaviour.
- Public API additions get a bullet under `## 0.1.0 - Unreleased` / `### Added` in `packages/token_manager_gql/CHANGELOG.md` in the same commit.
- Do not touch `packages/token_manager`, `packages/token_manager_dio` or `packages/token_manager_grpc`.
- All code, comments and docs are in English.

## Review Focus

The rulings imply these inputs, but no happy-path test exercises them; each has a pinning test in the task named in brackets.

1. A 401 whose body is not GraphQL JSON reaches the link as `HttpLinkParserException` (a `ResponseFormatException` without a status code): by default it is delivered without a replay, and a subclass of `AuthFailureMatcher` can opt in. [Task 2: `a ResponseFormatException is not an auth error by default`, `a subclass can recognise more errors`]
2. The request already carries an `Authorization` header (set by the app or another link): the token header must win, other headers must stay. [Task 3: `the token header replaces the same header on the request`]
3. The refresh triggered by the replay fails terminally (`InvalidGrant`): the stream must end with `InvalidGrant`, not with the stale 401, and nothing is sent a second time. [Task 3: `a terminal refresh failure during the replay is delivered`]
4. An auth failure arrives after a first response (multi-response streams such as `@defer`): it must be delivered, never replayed, so the client sees no duplicate data. [Task 3: `a 401 after the first response is delivered unreplayed`]
5. The WebSocket client reports two auth closes in a row (a reconnect storm): one refresh only, and both calls ask for an immediate reconnect. [Task 5: `two auth closes in a row refresh once`]

---

## File structure

Created in `packages/token_manager_gql/`:

| File | Responsibility |
|---|---|
| `pubspec.yaml` | package metadata, constraints, the gql_exec retraction comment |
| `.gitignore`, `LICENSE` | copied from `packages/token_manager_dio/` and `packages/token_manager/` |
| `CHANGELOG.md` | `0.1.0 - Unreleased`, one bullet per public type |
| `README.md` | usage, chain order, failure channels, anonymous operations, subscriptions and what stays the app's job, constraints |
| `example/main.dart` | runnable example with an in-process fake server link (no network) |
| `lib/token_manager_gql.dart` | the only public barrel |
| `lib/src/auth_failure_matcher.dart` | `AuthFailureMatcher`: recognises a rejection on either channel; extensible |
| `lib/src/skip_authorization.dart` | `SkipAuthorization`: `ContextEntry` that marks an anonymous request |
| `lib/src/token_manager_link.dart` | `TokenManagerLink<T>` and the private `_RejectedResponse` carrier |
| `lib/src/token_manager_socket_auth.dart` | `TokenManagerSocketAuth<T>`: `initialPayload` and `onConnectionLost` callbacks |
| `test/helpers/size_limits.dart` | verbatim copy of the core's ratchet helper |
| `test/helpers/counting_refresher.dart` | `CountingRefresher`: returns `fresh-<n>` or throws a set failure |
| `test/helpers/fake_terminal_link.dart` | `FakeTerminalLink`: scripted terminating link that records requests and stream controllers |
| `test/helpers/link_fixture.dart` | `LinkFixture`: wires manager + link + fake terminal; builds requests and responses |
| `test/quality/size_limits_test.dart` | the ratchet, empty allowlists |
| `test/auth_failure_matcher_test.dart` | matcher rules |
| `test/token_manager_link_test.dart` | header, error-channel replay, anonymous, concurrency, misuse |
| `test/token_manager_link_lifecycle_test.dart` | laziness, pause, resume, cancel, no replay after the first response |
| `test/token_manager_link_response_test.dart` | response-channel replay and the `data == null` rule |
| `test/token_manager_socket_auth_test.dart` | the WebSocket helper |

Modified: root `pubspec.yaml` (workspace list).

---

### Task 1: Scaffold the package and its size-limits ratchet

**Files:**
- Modify: `pubspec.yaml` (root, `workspace:` list)
- Create: `packages/token_manager_gql/pubspec.yaml`
- Create: `packages/token_manager_gql/.gitignore` (copy), `packages/token_manager_gql/LICENSE` (copy)
- Create: `packages/token_manager_gql/CHANGELOG.md`
- Create: `packages/token_manager_gql/lib/token_manager_gql.dart`
- Create: `packages/token_manager_gql/test/helpers/size_limits.dart` (copy)
- Test: `packages/token_manager_gql/test/quality/size_limits_test.dart` (copy)

**Interfaces:**
- Consumes: `packages/token_manager/test/helpers/size_limits.dart` (`SizeLimits(String packageRoot)`, `fileFailures({required Map<String, int> allowlist, required Set<String> permanent})`, `methodFailures({required Map<String, int> allowlist})`), copied verbatim.
- Produces: a resolvable workspace package `token_manager_gql` with the barrel `package:token_manager_gql/token_manager_gql.dart` (no exports yet) and `CHANGELOG.md` with an empty `### Added` section that later tasks append to.

- [ ] **Step 1: Add the package to the workspace**

In the root `pubspec.yaml`, replace the `workspace:` list with:

```yaml
workspace:
  - packages/token_manager
  - packages/token_manager_dio
  - packages/token_manager_gql
  - packages/token_manager_grpc
```

- [ ] **Step 2: Write the package pubspec**

Create `packages/token_manager_gql/pubspec.yaml`:

```yaml
name: token_manager_gql
description: A gql_link Link that attaches token_manager tokens to GraphQL requests and replays once after an auth failure.
version: 0.1.0
repository: https://github.com/4akloon/dart_token_manager
homepage: https://github.com/4akloon/dart_token_manager
issue_tracker: https://github.com/4akloon/dart_token_manager/issues
topics:
  - graphql
  - gql
  - authentication

environment:
  sdk: ^3.10.0

resolution: workspace

# gql_exec 1.1.0 is retracted while gql_link 1.1.0 requires gql_exec ^1.1.0,
# so `^1.0.0` resolves to the stable pair gql_link 1.0.0+1 and gql_exec
# 1.0.0+1. Their lib/ API is the same as gql_link 1.1.0. Do not raise the
# floor to 1.1.0: it only resolves to a gql_exec prerelease. `^1.0.0` is also
# what graphql 5.x requires, and ferry accepts gql_link <2.0.0.
dependencies:
  gql_exec: ^1.0.0
  gql_link: ^1.0.0
  token_manager: ^0.1.0

dev_dependencies:
  gql: ^1.0.0
  test: ^1.31.0
```

`token_manager: ^0.1.0` matches the core's current `version: 0.1.0`; a workspace constraint must allow the local version. See the open question at the end of the plan about bumping it to `^0.2.0` together with the core.

- [ ] **Step 3: Copy the boilerplate and the ratchet**

```bash
mkdir -p packages/token_manager_gql/lib packages/token_manager_gql/test/helpers packages/token_manager_gql/test/quality
cp packages/token_manager_dio/.gitignore packages/token_manager_gql/.gitignore
cp packages/token_manager/LICENSE packages/token_manager_gql/LICENSE
cp packages/token_manager/test/helpers/size_limits.dart packages/token_manager_gql/test/helpers/size_limits.dart
cp packages/token_manager/test/quality/size_limits_test.dart packages/token_manager_gql/test/quality/size_limits_test.dart
```

Both test files are copied unchanged: `size_limits_test.dart` measures `SizeLimits('.')`, the package that runs `dart test`, and its three allowlists (`_fileAllowlist`, `_permanent`, `_methodAllowlist`) stay empty. Never add entries.

- [ ] **Step 4: Write the barrel and the changelog**

Create `packages/token_manager_gql/lib/token_manager_gql.dart`:

```dart
/// A gql_link `Link` that attaches token_manager tokens to GraphQL requests
/// and replays a request once after an auth failure.
library;
```

Create `packages/token_manager_gql/CHANGELOG.md`:

```markdown
## 0.1.0 - Unreleased

### Added
```

- [ ] **Step 5: Resolve and check the versions**

Run: `dart pub get`
Expected: succeeds. Then run `grep -A7 -E '^  gql(_exec|_link)?:' pubspec.lock | grep -E '^  g|version'`
Expected:

```
  gql:
    version: "1.0.1"
  gql_exec:
    version: "1.0.0+1"
  gql_link:
    version: "1.0.0+1"
```

If `gql_exec` resolves to a `1.1.1-alpha` prerelease, a constraint was raised to `^1.1.0`: restore `^1.0.0`.

- [ ] **Step 6: Run the ratchet**

Run: `cd packages/token_manager_gql && dart test`
Expected: PASS, 2 tests (`no file is over its size limit unless it is allowlisted`, `no method is over 40 lines unless it is allowlisted`).

- [ ] **Step 7: Format and analyze**

Run: `dart format packages && dart format packages && dart analyze packages`
Expected: the second format run reports `0 changed`; analyze prints `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml packages/token_manager_gql
git commit -m "build(token_manager_gql): scaffold the package and its size ratchet

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: AuthFailureMatcher

**Files:**
- Create: `packages/token_manager_gql/lib/src/auth_failure_matcher.dart`
- Modify: `packages/token_manager_gql/lib/token_manager_gql.dart`
- Modify: `packages/token_manager_gql/CHANGELOG.md`
- Test: `packages/token_manager_gql/test/auth_failure_matcher_test.dart`

**Interfaces:**
- Consumes: `ServerException` (`int? statusCode`), `ResponseFormatException` from `package:gql_link/gql_link.dart`; `Response` (`List<GraphQLError>? errors`), `GraphQLError` (`Map<String, dynamic>? extensions`) from `package:gql_exec/gql_exec.dart`.
- Produces: `class AuthFailureMatcher` (not `final`: apps extend it) with
  - `const AuthFailureMatcher({Set<int> statusCodes = const {401}, Set<String> errorCodes = const {'UNAUTHENTICATED'}})`
  - `final Set<int> statusCodes;` `final Set<String> errorCodes;`
  - `bool isAuthError(Object error)`: `error is ServerException && statusCodes.contains(error.statusCode)`
  - `bool isAuthResponse(Response response)`: some `errors[].extensions['code']` is a `String` in `errorCodes`. It does **not** look at `data`; the `data == null` rule lives in `TokenManagerLink` (Task 4) so a custom matcher cannot enable mutation replays.

- [ ] **Step 1: Write the failing tests**

Create `packages/token_manager_gql/test/auth_failure_matcher_test.dart`:

```dart
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:test/test.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

Response _responseWithCode(Object? code) => Response(
  errors: [
    GraphQLError(message: 'failed', extensions: {'code': code}),
  ],
  response: const {},
);

/// Also treats a body that is not GraphQL JSON as a rejection, as an app
/// whose server answers 401 with an HTML page would.
final class _ParserAwareMatcher extends AuthFailureMatcher {
  const _ParserAwareMatcher();

  @override
  bool isAuthError(Object error) =>
      error is ResponseFormatException || super.isAuthError(error);
}

void main() {
  const matcher = AuthFailureMatcher();

  test('a ServerException with status 401 is an auth error', () {
    expect(matcher.isAuthError(const ServerException(statusCode: 401)), isTrue);
  });

  test('a ServerException with another status is not an auth error', () {
    expect(
      matcher.isAuthError(const ServerException(statusCode: 500)),
      isFalse,
    );
  });

  test('a ServerException without a status is not an auth error', () {
    expect(matcher.isAuthError(const ServerException()), isFalse);
  });

  test('an exception that is not a ServerException is not an auth error', () {
    expect(matcher.isAuthError(const FormatException('401')), isFalse);
  });

  test('a response with the UNAUTHENTICATED code is an auth response', () {
    expect(
      matcher.isAuthResponse(_responseWithCode('UNAUTHENTICATED')),
      isTrue,
    );
  });

  test('a response with another code is not an auth response', () {
    expect(matcher.isAuthResponse(_responseWithCode('FORBIDDEN')), isFalse);
  });

  test('a response whose code is not a string is not an auth response', () {
    expect(matcher.isAuthResponse(_responseWithCode(401)), isFalse);
  });

  test('a response without errors is not an auth response', () {
    const response = Response(data: {'me': 'ada'}, response: {});
    expect(matcher.isAuthResponse(response), isFalse);
  });

  test('a response whose error has no extensions is not an auth response', () {
    const response = Response(
      errors: [GraphQLError(message: 'failed')],
      response: {},
    );
    expect(matcher.isAuthResponse(response), isFalse);
  });

  test('custom status and error codes replace the defaults', () {
    const custom = AuthFailureMatcher(
      statusCodes: {419},
      errorCodes: {'invalid-jwt'},
    );
    expect(custom.isAuthError(const ServerException(statusCode: 419)), isTrue);
    expect(custom.isAuthError(const ServerException(statusCode: 401)), isFalse);
    expect(custom.isAuthResponse(_responseWithCode('invalid-jwt')), isTrue);
  });

  test('a ResponseFormatException is not an auth error by default', () {
    expect(matcher.isAuthError(const ResponseFormatException()), isFalse);
  });

  test('a subclass can recognise more errors', () {
    const parserAware = _ParserAwareMatcher();
    expect(parserAware.isAuthError(const ResponseFormatException()), isTrue);
    expect(
      parserAware.isAuthError(const ServerException(statusCode: 401)),
      isTrue,
    );
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/token_manager_gql && dart test test/auth_failure_matcher_test.dart`
Expected: FAIL to compile: `Type 'AuthFailureMatcher' not found` / `Method not found: 'AuthFailureMatcher'`.

- [ ] **Step 3: Implement the matcher**

Create `packages/token_manager_gql/lib/src/auth_failure_matcher.dart`:

```dart
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';

/// Decides whether a GraphQL failure means the server rejected the tokens.
///
/// A failure arrives on one of two channels: an error event, such as a
/// [ServerException] for an HTTP 401, or a [Response] whose `errors` carry an
/// auth code, such as `extensions.code: "UNAUTHENTICATED"` in an HTTP 200.
/// Extend this class to recognise other failures, for example the
/// `HttpLinkParserException` that `HttpLink` emits for a 401 whose body is not
/// GraphQL JSON.
class AuthFailureMatcher {
  /// Creates a matcher for the HTTP [statusCodes] of a [ServerException] and
  /// the [errorCodes] in `errors[].extensions.code` of a [Response].
  const AuthFailureMatcher({
    this.statusCodes = const {401},
    this.errorCodes = const {'UNAUTHENTICATED'},
  });

  /// The HTTP status codes that mean the tokens were rejected.
  final Set<int> statusCodes;

  /// The `extensions.code` values that mean the tokens were rejected.
  final Set<String> errorCodes;

  /// Whether the error event [error] means the tokens were rejected.
  bool isAuthError(Object error) =>
      error is ServerException && statusCodes.contains(error.statusCode);

  /// Whether one of the `errors` of [response] means the tokens were rejected.
  bool isAuthResponse(Response response) =>
      response.errors?.any(_isAuthGraphQLError) ?? false;

  bool _isAuthGraphQLError(GraphQLError error) {
    final code = error.extensions?['code'];
    return code is String && errorCodes.contains(code);
  }
}
```

Replace `packages/token_manager_gql/lib/token_manager_gql.dart` with:

```dart
/// A gql_link `Link` that attaches token_manager tokens to GraphQL requests
/// and replays a request once after an auth failure.
library;

export 'src/auth_failure_matcher.dart' show AuthFailureMatcher;
```

Append to `packages/token_manager_gql/CHANGELOG.md` under `### Added`:

```markdown
- `AuthFailureMatcher`, which recognises a rejection: HTTP 401 and the
  `UNAUTHENTICATED` error code by default.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/token_manager_gql && dart test`
Expected: PASS (12 matcher tests + 2 ratchet tests).

- [ ] **Step 5: Format and analyze**

Run: `dart format packages && dart format packages && dart analyze packages`
Expected: second format run `0 changed`; `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add packages/token_manager_gql
git commit -m "feat(token_manager_gql): add AuthFailureMatcher

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: TokenManagerLink on the error channel, with SkipAuthorization

**Files:**
- Create: `packages/token_manager_gql/lib/src/skip_authorization.dart`
- Create: `packages/token_manager_gql/lib/src/token_manager_link.dart`
- Modify: `packages/token_manager_gql/lib/token_manager_gql.dart`
- Modify: `packages/token_manager_gql/CHANGELOG.md`
- Create: `packages/token_manager_gql/test/helpers/counting_refresher.dart`
- Create: `packages/token_manager_gql/test/helpers/fake_terminal_link.dart`
- Create: `packages/token_manager_gql/test/helpers/link_fixture.dart`
- Test: `packages/token_manager_gql/test/token_manager_link_test.dart`
- Test: `packages/token_manager_gql/test/token_manager_link_lifecycle_test.dart`

**Interfaces:**
- Consumes:
  - from Task 2: `AuthFailureMatcher` with `bool isAuthError(Object error)`.
  - from the core (`package:token_manager/token_manager.dart`): `TokenManager<T>.create({required TokenStore<T> store, TokenRefresher<T>? refresher, TokenInfo<T>? info, ...})`, `Stream<R> authorizeStream<R>(Stream<R> Function(T tokens) open, {required bool Function(Object error) isAuthFailure})`, `Future<T> validToken({T? rejected})`, `TokenSet({required String accessToken, String? refreshToken, DateTime? expiresAt})`, `InMemoryTokenStore<T>([T? initial])`, `TokenRefresher<T>`, `NotAuthenticated`, `InvalidGrant`. `authorizeStream` acquires the token on listen, opens the source with `listen`, replays once on an error event accepted by `isAuthFailure` **before the first data event**, cancels the stale source before renewing, forwards the original error when `validToken(rejected:)` returns the identical token, and emits manager failures as an error followed by done.
  - from gql: `Link` (`Stream<Response> request(Request request, [NextLink? forward])`), `NextLink`, `Link.from(List<Link>)`, `ServerException`; `Request.context.entry<T>()`, `Request.updateContextEntry<T>(T? Function(T? entry))`, `Request.withContextEntry<T>(T entry)`, `Context`, `ContextEntry` (`List<Object?> get fieldsForEquality`), `HttpLinkHeaders({Map<String, String> headers})`, `Operation({required DocumentNode document})`, `parseString` (`package:gql/language.dart`).
- Produces:
  - `final class SkipAuthorization extends ContextEntry` with `const SkipAuthorization()`.
  - `final class TokenManagerLink<T> extends Link` with `TokenManagerLink({required TokenManager<T> manager, required Map<String, String> Function(T tokens) headers, AuthFailureMatcher matcher = const AuthFailureMatcher()})` and `Stream<Response> request(Request request, [NextLink? forward])`; private `Stream<Response> _send(Request original, T tokens, NextLink forward)` (Task 4 extends it).
  - Test helpers used by Tasks 4 and 5:
    - `CountingRefresher({Exception? failure})` implementing `TokenRefresher<TokenSet>`, `int get calls`; call `n` returns `TokenSet(accessToken: 'fresh-n')` or throws `failure`.
    - `FakeTerminalLink([List<Object> outcomes = const []])`: `List<Request> requests`, `List<StreamController<Response>> controllers`, `String? authorizationOf(int index)`.
    - `LinkFixture({List<Object> outcomes = const [], bool isSignedIn = true, bool hasRefresher = true, Exception? refreshFailure})` with `manager`, `refresher`, `terminal`, `link`, `static const ServerException unauthorized`, `static const Response ok`, `Request query({Context context = const Context()})`, `Future<List<Object>> send(Request request)`.

- [ ] **Step 1: Write the test helpers**

Create `packages/token_manager_gql/test/helpers/counting_refresher.dart`:

```dart
import 'package:token_manager/token_manager.dart';

/// A refresher that counts its calls and returns `fresh-<n>` on call `n`, or
/// throws [failure] when one is set.
final class CountingRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher that succeeds, or always throws [failure].
  CountingRefresher({this.failure});

  /// What every call throws; `null` makes calls succeed.
  final Exception? failure;

  int _calls = 0;

  /// How many times [refresh] was called.
  int get calls => _calls;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    _calls++;
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    return TokenSet(accessToken: 'fresh-$_calls');
  }
}
```

Create `packages/token_manager_gql/test/helpers/fake_terminal_link.dart`:

```dart
import 'dart:async';

import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';

/// A terminating link that answers each request with a scripted outcome and
/// records what it was sent.
final class FakeTerminalLink extends Link {
  /// Answers request number `i` with `outcomes[i]`: a [Response] is emitted
  /// as an event, anything else as an error event, and the stream then ends.
  /// A request past the script gets a stream that stays open.
  FakeTerminalLink([this._outcomes = const []]);

  final List<Object> _outcomes;

  /// The requests received, in order.
  final List<Request> requests = [];

  /// The controller behind the stream of each request, in order.
  final List<StreamController<Response>> controllers = [];

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final index = requests.length;
    requests.add(request);
    final controller = StreamController<Response>();
    controllers.add(controller);
    if (index < _outcomes.length) {
      switch (_outcomes[index]) {
        case final Response response:
          controller.add(response);
        case final Object error:
          controller.addError(error);
      }
      unawaited(controller.close());
    }
    return controller.stream;
  }

  /// The `Authorization` header of request number [index], if any.
  String? authorizationOf(int index) => requests[index].context
      .entry<HttpLinkHeaders>()
      ?.headers['Authorization'];
}
```

Create `packages/token_manager_gql/test/helpers/link_fixture.dart`:

```dart
import 'dart:async';

import 'package:gql/language.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

import 'counting_refresher.dart';
import 'fake_terminal_link.dart';

/// Wires a [TokenManagerLink] between a [TokenManager] and a
/// [FakeTerminalLink], and builds requests and responses for it.
final class LinkFixture {
  /// Creates a fixture whose terminal answers with [outcomes]; the session
  /// holds the token `old` when [isSignedIn], and refreshes through
  /// [refresher] when [hasRefresher], which throws [refreshFailure] when it
  /// is set.
  factory LinkFixture({
    List<Object> outcomes = const [],
    bool isSignedIn = true,
    bool hasRefresher = true,
    Exception? refreshFailure,
  }) {
    final refresher = CountingRefresher(failure: refreshFailure);
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(
        isSignedIn ? const TokenSet(accessToken: 'old') : null,
      ),
      refresher: hasRefresher ? refresher : null,
    );
    return LinkFixture._(manager, refresher, FakeTerminalLink(outcomes));
  }

  LinkFixture._(this.manager, this.refresher, this.terminal)
    : link = Link.from([
        TokenManagerLink<TokenSet>(
          manager: manager,
          headers: (tokens) => {
            'Authorization': 'Bearer ${tokens.accessToken}',
          },
        ),
        terminal,
      ]);

  /// An HTTP 401 as `HttpLink` reports it.
  static const ServerException unauthorized = ServerException(statusCode: 401);

  /// A successful response.
  static const Response ok = Response(data: {'me': 'ada'}, response: {});

  /// The session's manager.
  final TokenManager<TokenSet> manager;

  /// The manager's refresher.
  final CountingRefresher refresher;

  /// The link after the [TokenManagerLink].
  final FakeTerminalLink terminal;

  /// The chain under test: [TokenManagerLink] then [terminal].
  final Link link;

  /// A query request with [context].
  Request query({Context context = const Context()}) => Request(
    operation: Operation(document: parseString('query Me { me }')),
    context: context,
  );

  /// Sends [request] through [link] and collects every event and error until
  /// the stream ends.
  Future<List<Object>> send(Request request) {
    final events = <Object>[];
    final done = Completer<List<Object>>();
    link
        .request(request)
        .listen(
          events.add,
          onError: events.add,
          onDone: () => done.complete(events),
        );
    return done.future;
  }
}
```

No `info` is passed to the manager, so `old` never expires: the first `validToken()` returns it without a refresh, and only a rejection refreshes.

- [ ] **Step 2: Write the failing link tests**

Create `packages/token_manager_gql/test/token_manager_link_test.dart`:

```dart
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

import 'helpers/link_fixture.dart';

void main() {
  test('attaches the header built from valid tokens', () async {
    final fixture = LinkFixture(outcomes: [LinkFixture.ok]);

    final events = await fixture.send(fixture.query());

    expect(events, [LinkFixture.ok]);
    expect(fixture.terminal.authorizationOf(0), 'Bearer old');
  });

  test('keeps the headers the request already carries', () async {
    final fixture = LinkFixture(outcomes: [LinkFixture.ok]);
    const traced = HttpLinkHeaders(headers: {'X-Trace': '1'});

    await fixture.send(
      fixture.query(context: const Context().withEntry(traced)),
    );

    final headers = fixture.terminal.requests.single.context
        .entry<HttpLinkHeaders>()
        ?.headers;
    expect(headers, {'X-Trace': '1', 'Authorization': 'Bearer old'});
  });

  test('the token header replaces the same header on the request', () async {
    final fixture = LinkFixture(outcomes: [LinkFixture.ok]);
    const stale = HttpLinkHeaders(headers: {'Authorization': 'Bearer stale'});

    await fixture.send(
      fixture.query(context: const Context().withEntry(stale)),
    );

    expect(fixture.terminal.authorizationOf(0), 'Bearer old');
  });

  test('replays once with refreshed tokens after a 401 error event', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.unauthorized, LinkFixture.ok],
    );

    final events = await fixture.send(fixture.query());

    expect(events, [LinkFixture.ok]);
    expect(fixture.terminal.authorizationOf(1), 'Bearer fresh-1');
    expect(fixture.refresher.calls, 1);
  });

  test(
    'a persistent 401 is replayed exactly once and then delivered',
    () async {
      final fixture = LinkFixture(
        outcomes: [LinkFixture.unauthorized, LinkFixture.unauthorized],
      );

      final events = await fixture.send(fixture.query());

      expect(events, [LinkFixture.unauthorized]);
      expect(fixture.terminal.requests, hasLength(2));
    },
  );

  test(
    'an error the matcher does not accept is delivered unreplayed',
    () async {
      const failure = ServerException(statusCode: 500);
      final fixture = LinkFixture(outcomes: [failure]);

      final events = await fixture.send(fixture.query());

      expect(events, [failure]);
      expect(fixture.refresher.calls, 0);
    },
  );

  test('a terminal refresh failure during the replay is delivered', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.unauthorized, LinkFixture.ok],
      refreshFailure: const InvalidGrant(),
    );

    final events = await fixture.send(fixture.query());

    expect(events, [isA<InvalidGrant>()]);
    expect(fixture.terminal.requests, hasLength(1));
  });

  test('every attempt is built from the original request', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.unauthorized, LinkFixture.ok],
    );
    const traced = HttpLinkHeaders(headers: {'X-Trace': '1'});
    final original = fixture.query(context: const Context().withEntry(traced));

    await fixture.send(original);

    final expected = original.withContextEntry(
      const HttpLinkHeaders(
        headers: {'X-Trace': '1', 'Authorization': 'Bearer fresh-1'},
      ),
    );
    expect(fixture.terminal.requests[1], expected);
  });

  test('concurrent rejected requests share one refresh', () async {
    final fixture = LinkFixture(
      outcomes: [
        LinkFixture.unauthorized,
        LinkFixture.unauthorized,
        LinkFixture.ok,
        LinkFixture.ok,
      ],
    );

    final results = await Future.wait([
      fixture.send(fixture.query()),
      fixture.send(fixture.query()),
    ]);

    expect(results, [
      [LinkFixture.ok],
      [LinkFixture.ok],
    ]);
    expect(fixture.refresher.calls, 1);
  });

  test(
    'a request marked with SkipAuthorization is sent without tokens',
    () async {
      final fixture = LinkFixture(
        outcomes: [LinkFixture.ok],
        isSignedIn: false,
      );
      final anonymous = fixture.query(
        context: const Context().withEntry(const SkipAuthorization()),
      );

      final events = await fixture.send(anonymous);

      expect(events, [LinkFixture.ok]);
      expect(fixture.terminal.requests.single, anonymous);
    },
  );

  test('a request without a session fails with NotAuthenticated', () async {
    final fixture = LinkFixture(outcomes: [LinkFixture.ok], isSignedIn: false);

    final events = await fixture.send(fixture.query());

    expect(events, [isA<NotAuthenticated>()]);
    expect(fixture.terminal.requests, isEmpty);
  });

  test('throws a StateError when it terminates the chain', () {
    final fixture = LinkFixture();
    final link = TokenManagerLink<TokenSet>(
      manager: fixture.manager,
      headers: (tokens) => const {},
    );

    expect(() => link.request(fixture.query()), throwsStateError);
  });
}
```

`every attempt is built from the original request` compares whole `Request`s (deep equality over operation, variables and context), so a replay built from the first, already-headered attempt or one that drops the `X-Trace` header fails it.

- [ ] **Step 3: Write the failing lifecycle tests**

Create `packages/token_manager_gql/test/token_manager_link_lifecycle_test.dart`:

```dart
import 'package:test/test.dart';

import 'helpers/link_fixture.dart';

void main() {
  test('nothing is sent until the stream is listened to', () async {
    final fixture = LinkFixture(outcomes: [LinkFixture.ok]);

    final stream = fixture.link.request(fixture.query());
    await pumpEventQueue();
    expect(fixture.terminal.requests, isEmpty);

    await expectLater(stream, emitsInOrder([LinkFixture.ok, emitsDone]));
  });

  test('pause and resume reach the terminating link', () async {
    final fixture = LinkFixture();
    final subscription = fixture.link.request(fixture.query()).listen(null);
    await pumpEventQueue();

    subscription.pause();
    expect(fixture.terminal.controllers.single.isPaused, isTrue);
    subscription.resume();
    expect(fixture.terminal.controllers.single.isPaused, isFalse);

    await subscription.cancel();
  });

  test('cancel reaches the terminating link', () async {
    final fixture = LinkFixture();
    final subscription = fixture.link.request(fixture.query()).listen(null);
    await pumpEventQueue();

    await subscription.cancel();

    expect(fixture.terminal.controllers.single.hasListener, isFalse);
  });

  test('cancelling before the tokens arrive never sends the request', () async {
    final fixture = LinkFixture();
    final subscription = fixture.link.request(fixture.query()).listen(null);

    await subscription.cancel();
    await pumpEventQueue();

    expect(fixture.terminal.requests, isEmpty);
  });

  test('a 401 after the first response is delivered unreplayed', () async {
    final fixture = LinkFixture();
    final events = <Object>[];
    final subscription = fixture.link
        .request(fixture.query())
        .listen(events.add, onError: events.add);
    await pumpEventQueue();

    fixture.terminal.controllers.single
      ..add(LinkFixture.ok)
      ..addError(LinkFixture.unauthorized);
    await pumpEventQueue();

    expect(events, [LinkFixture.ok, LinkFixture.unauthorized]);
    expect(fixture.terminal.requests, hasLength(1));
    await subscription.cancel();
  });
}
```

The controllers are read through `fixture.terminal.controllers.single` instead of a local variable: a local `StreamController` that is never closed trips the `close_sinks` lint.

- [ ] **Step 4: Run the tests to verify they fail**

Run: `cd packages/token_manager_gql && dart test test/token_manager_link_test.dart test/token_manager_link_lifecycle_test.dart`
Expected: FAIL to compile: `Type 'TokenManagerLink' not found`, `Method not found: 'SkipAuthorization'`.

- [ ] **Step 5: Implement SkipAuthorization**

Create `packages/token_manager_gql/lib/src/skip_authorization.dart`:

```dart
import 'package:gql_exec/gql_exec.dart';

/// Marks a request that must be sent without tokens, such as a login.
///
/// `TokenManagerLink` forwards a request whose context holds this entry
/// unchanged: it attaches no header, never asks for tokens and never replays.
final class SkipAuthorization extends ContextEntry {
  /// Creates the marker.
  const SkipAuthorization();

  @override
  List<Object?> get fieldsForEquality => const [];
}
```

- [ ] **Step 6: Implement the link (error channel only)**

Create `packages/token_manager_gql/lib/src/token_manager_link.dart`:

```dart
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:token_manager/token_manager.dart';

import 'auth_failure_matcher.dart';
import 'skip_authorization.dart';

/// Attaches tokens to GraphQL requests and replays a request once after the
/// server rejects them.
///
/// Put it right before the terminating link, after a `DedupeLink`:
/// `Link.from([DedupeLink(), TokenManagerLink(...), HttpLink(...)])`. Never
/// combine it with graphql's `AuthLink`. The link never refreshes by itself:
/// it asks the [TokenManager] for valid tokens and reports the rejected ones.
///
/// A rejection is an error event that [AuthFailureMatcher.isAuthError]
/// accepts. Only a rejection before the first response is replayed, and only
/// once; when the replay is rejected too, its error is delivered as is.
final class TokenManagerLink<T> extends Link {
  /// Creates a link that sends the [headers] built from the [manager]'s tokens
  /// and recognises rejections with [matcher].
  TokenManagerLink({
    required TokenManager<T> manager,
    required Map<String, String> Function(T tokens) headers,
    AuthFailureMatcher matcher = const AuthFailureMatcher(),
  }) : _manager = manager,
       _headers = headers,
       _matcher = matcher;

  final TokenManager<T> _manager;
  final Map<String, String> Function(T tokens) _headers;
  final AuthFailureMatcher _matcher;

  /// Sends [request] through [forward] with valid tokens.
  ///
  /// A request marked with [SkipAuthorization] is forwarded unchanged. The
  /// manager's failures (`NotAuthenticated`, `InvalidGrant`, `Transient`)
  /// arrive as error events. Throws a [StateError] when [forward] is null:
  /// this link cannot terminate a chain.
  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    if (forward == null) {
      throw StateError(
        'TokenManagerLink cannot terminate a chain; put a terminating link '
        'such as HttpLink after it.',
      );
    }
    if (request.context.entry<SkipAuthorization>() != null) {
      return forward(request);
    }
    return _manager.authorizeStream<Response>(
      (tokens) => _send(request, tokens, forward),
      isAuthFailure: _matcher.isAuthError,
    );
  }

  /// Sends a copy of [original] that carries the headers of [tokens]; every
  /// attempt starts from [original], never from an earlier attempt.
  Stream<Response> _send(Request original, T tokens, NextLink forward) {
    final authorized = original.updateContextEntry<HttpLinkHeaders>(
      (entry) => HttpLinkHeaders(
        headers: {...?entry?.headers, ..._headers(tokens)},
      ),
    );
    return forward(authorized);
  }
}
```

The `StateError` is a programming error (the link was put last in the chain); it is thrown, never caught, per CLAUDE.md.

- [ ] **Step 7: Export the new types and record them**

Replace `packages/token_manager_gql/lib/token_manager_gql.dart` with:

```dart
/// A gql_link `Link` that attaches token_manager tokens to GraphQL requests
/// and replays a request once after an auth failure.
library;

export 'src/auth_failure_matcher.dart' show AuthFailureMatcher;
export 'src/skip_authorization.dart' show SkipAuthorization;
export 'src/token_manager_link.dart' show TokenManagerLink;
```

In `packages/token_manager_gql/CHANGELOG.md`, insert above the `AuthFailureMatcher` bullet so the list reads:

```markdown
### Added
- `TokenManagerLink<T>`, a `gql_link` `Link` that attaches the tokens of a
  `TokenManager<T>` and replays a request once after the server rejects them
  on an error event.
- `AuthFailureMatcher`, which recognises a rejection: HTTP 401 and the
  `UNAUTHENTICATED` error code by default.
- `SkipAuthorization`, a request context entry for operations sent without
  tokens, such as a login.
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd packages/token_manager_gql && dart test`
Expected: PASS (12 link + 5 lifecycle + 12 matcher + 2 ratchet = 31 tests).

- [ ] **Step 9: Format and analyze**

Run: `dart format packages && dart format packages && dart analyze packages`
Expected: second format run `0 changed`; `No issues found!`.

- [ ] **Step 10: Commit**

```bash
git add packages/token_manager_gql
git commit -m "feat(token_manager_gql): add TokenManagerLink and SkipAuthorization

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Replay a rejected response that has no data

**Files:**
- Modify: `packages/token_manager_gql/lib/src/token_manager_link.dart` (whole file replaced)
- Modify: `packages/token_manager_gql/test/helpers/link_fixture.dart` (add `rejected`)
- Modify: `packages/token_manager_gql/CHANGELOG.md`
- Test: `packages/token_manager_gql/test/token_manager_link_response_test.dart`

**Interfaces:**
- Consumes: from Task 2 `bool AuthFailureMatcher.isAuthResponse(Response response)`; from Task 3 `TokenManagerLink` (`_send`, `request`), `LinkFixture`, `FakeTerminalLink`, `CountingRefresher`. `authorizeStream` consults `isAuthFailure` only for error events and only before the first data event, so a rejected `Response` must become an error event inside the `open` callback.
- Produces:
  - `static Response LinkFixture.rejected({String code = 'UNAUTHENTICATED', String message = 'not signed in', Map<String, Object?>? data})`.
  - `TokenManagerLink` behaviour: a `Response` with `data == null` that `isAuthResponse` accepts is replayed once; when it is not replayed (second rejection, or no replacement token) the client receives that `Response` as a data event, never an error. A response with `data != null` is never replayed. The private `_RejectedResponse implements Exception` never leaves the link.

- [ ] **Step 1: Add the response builder to the fixture**

In `packages/token_manager_gql/test/helpers/link_fixture.dart`, insert after the `query` method:

```dart
  /// A response whose error has `extensions.code` [code] and whose data is
  /// [data].
  static Response rejected({
    String code = 'UNAUTHENTICATED',
    String message = 'not signed in',
    Map<String, Object?>? data,
  }) => Response(
    data: data,
    errors: [
      GraphQLError(message: message, extensions: {'code': code}),
    ],
    response: const {},
  );
```

- [ ] **Step 2: Write the failing tests**

Create `packages/token_manager_gql/test/token_manager_link_response_test.dart`:

```dart
import 'package:test/test.dart';

import 'helpers/link_fixture.dart';

void main() {
  test('replays an UNAUTHENTICATED response that has no data', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.rejected(), LinkFixture.ok],
    );

    final events = await fixture.send(fixture.query());

    expect(events, [LinkFixture.ok]);
    expect(fixture.terminal.authorizationOf(1), 'Bearer fresh-1');
    expect(fixture.refresher.calls, 1);
  });

  test('delivers an UNAUTHENTICATED response with data unreplayed', () async {
    final partial = LinkFixture.rejected(data: {'createPost': null});
    final fixture = LinkFixture(outcomes: [partial, LinkFixture.ok]);

    final events = await fixture.send(fixture.query());

    expect(events, [partial]);
    expect(fixture.terminal.requests, hasLength(1));
    expect(fixture.refresher.calls, 0);
  });

  test('a persistent UNAUTHENTICATED response is replayed once and then '
      'delivered as a response', () async {
    final first = LinkFixture.rejected();
    final second = LinkFixture.rejected(message: 'still not signed in');
    final fixture = LinkFixture(outcomes: [first, second]);

    final events = await fixture.send(fixture.query());

    expect(events, [second]);
    expect(fixture.terminal.requests, hasLength(2));
  });

  test('without a refresher the UNAUTHENTICATED response is delivered as '
      'is', () async {
    final rejected = LinkFixture.rejected();
    final fixture = LinkFixture(outcomes: [rejected], hasRefresher: false);

    final events = await fixture.send(fixture.query());

    expect(events, [rejected]);
    expect(fixture.terminal.requests, hasLength(1));
  });

  test('a response with another error code is delivered unreplayed', () async {
    final forbidden = LinkFixture.rejected(code: 'FORBIDDEN');
    final fixture = LinkFixture(outcomes: [forbidden]);

    final events = await fixture.send(fixture.query());

    expect(events, [forbidden]);
    expect(fixture.refresher.calls, 0);
  });
}
```

`{'createPost': null}` stands for a mutation whose field failed after it may already have run: the response has data, so it must never be sent twice. Without a refresher, `validToken(rejected:)` returns the identical token, `authorizeStream` forwards the original error, and the link must turn it back into the response.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/token_manager_gql && dart test test/token_manager_link_response_test.dart`
Expected: FAIL in exactly two tests, `replays an UNAUTHENTICATED response that has no data` and `a persistent UNAUTHENTICATED response is replayed once and then delivered as a response` (one request sent, the rejected response delivered). The other three already pass with the Task 3 link and pin that this task does not start replaying them.

- [ ] **Step 4: Implement the response channel**

Replace `packages/token_manager_gql/lib/src/token_manager_link.dart` with:

```dart
import 'dart:async';

import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:token_manager/token_manager.dart';

import 'auth_failure_matcher.dart';
import 'skip_authorization.dart';

/// Attaches tokens to GraphQL requests and replays a request once after the
/// server rejects them.
///
/// Put it right before the terminating link, after a `DedupeLink`:
/// `Link.from([DedupeLink(), TokenManagerLink(...), HttpLink(...)])`. Never
/// combine it with graphql's `AuthLink`. The link never refreshes by itself:
/// it asks the [TokenManager] for valid tokens and reports the rejected ones.
///
/// A rejection arrives as an error event that [AuthFailureMatcher.isAuthError]
/// accepts, or as a [Response] that [AuthFailureMatcher.isAuthResponse]
/// accepts and that has no `data`. A response with `data` is never replayed,
/// because a mutation may already have run. Only a rejection before the first
/// response is replayed, and only once; when the replay is rejected too, its
/// error or response is delivered as is.
final class TokenManagerLink<T> extends Link {
  /// Creates a link that sends the [headers] built from the [manager]'s tokens
  /// and recognises rejections with [matcher].
  TokenManagerLink({
    required TokenManager<T> manager,
    required Map<String, String> Function(T tokens) headers,
    AuthFailureMatcher matcher = const AuthFailureMatcher(),
  }) : _manager = manager,
       _headers = headers,
       _matcher = matcher;

  final TokenManager<T> _manager;
  final Map<String, String> Function(T tokens) _headers;
  final AuthFailureMatcher _matcher;

  /// Sends [request] through [forward] with valid tokens.
  ///
  /// A request marked with [SkipAuthorization] is forwarded unchanged. The
  /// manager's failures (`NotAuthenticated`, `InvalidGrant`, `Transient`)
  /// arrive as error events. Throws a [StateError] when [forward] is null:
  /// this link cannot terminate a chain.
  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    if (forward == null) {
      throw StateError(
        'TokenManagerLink cannot terminate a chain; put a terminating link '
        'such as HttpLink after it.',
      );
    }
    if (request.context.entry<SkipAuthorization>() != null) {
      return forward(request);
    }
    return _manager
        .authorizeStream<Response>(
          (tokens) => _send(request, tokens, forward),
          isAuthFailure: _isAuthFailure,
        )
        .transform(
          StreamTransformer<Response, Response>.fromHandlers(
            handleError: _deliverRejectedResponse,
          ),
        );
  }

  /// Sends a copy of [original] that carries the headers of [tokens]; every
  /// attempt starts from [original], never from an earlier attempt.
  Stream<Response> _send(Request original, T tokens, NextLink forward) {
    final authorized = original.updateContextEntry<HttpLinkHeaders>(
      (entry) => HttpLinkHeaders(
        headers: {...?entry?.headers, ..._headers(tokens)},
      ),
    );
    return forward(authorized).transform(
      StreamTransformer<Response, Response>.fromHandlers(
        handleData: _rejectUnauthenticated,
      ),
    );
  }

  /// Turns a rejected [response] without data into an error event, which is
  /// the only channel on which `authorizeStream` replays.
  void _rejectUnauthenticated(Response response, EventSink<Response> sink) {
    if (response.data == null && _matcher.isAuthResponse(response)) {
      sink.addError(_RejectedResponse(response));
    } else {
      sink.add(response);
    }
  }

  bool _isAuthFailure(Object error) =>
      error is _RejectedResponse || _matcher.isAuthError(error);

  /// Delivers a rejected response that was not replayed as the response it
  /// was, so the client sees the server's `errors` unchanged.
  void _deliverRejectedResponse(
    Object error,
    StackTrace stackTrace,
    EventSink<Response> sink,
  ) {
    if (error is _RejectedResponse) {
      sink.add(error.response);
    } else {
      sink.addError(error, stackTrace);
    }
  }
}

/// Carries a rejected [Response] through the error channel of
/// `authorizeStream`; it never leaves [TokenManagerLink].
final class _RejectedResponse implements Exception {
  const _RejectedResponse(this.response);

  final Response response;
}
```

Why `StreamTransformer.fromHandlers` and not `async*`: its bound stream forwards `pause`, `resume` and `cancel` to the stream it wraps, so the lifecycle tests of Task 3 keep passing; an `async*` body with `await for` would break them and the CLAUDE.md rule.

- [ ] **Step 5: Update the changelog bullet**

In `packages/token_manager_gql/CHANGELOG.md`, replace the `TokenManagerLink<T>` bullet with:

```markdown
- `TokenManagerLink<T>`, a `gql_link` `Link` that attaches the tokens of a
  `TokenManager<T>` and replays a request once after the server rejects them,
  on an error event or on a response without data whose errors carry an auth
  code.
```

- [ ] **Step 6: Run all tests to verify they pass**

Run: `cd packages/token_manager_gql && dart test`
Expected: PASS (36 tests). The Task 3 lifecycle tests must still pass: they prove the two transformers keep pause, resume and cancel intact.

- [ ] **Step 7: Format and analyze**

Run: `dart format packages && dart format packages && dart analyze packages`
Expected: second format run `0 changed`; `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add packages/token_manager_gql
git commit -m "feat(token_manager_gql): replay unauthenticated responses without data

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: TokenManagerSocketAuth for WebSocket subscriptions

**Files:**
- Create: `packages/token_manager_gql/lib/src/token_manager_socket_auth.dart`
- Modify: `packages/token_manager_gql/lib/token_manager_gql.dart`
- Modify: `packages/token_manager_gql/CHANGELOG.md`
- Test: `packages/token_manager_gql/test/token_manager_socket_auth_test.dart`

**Interfaces:**
- Consumes: `TokenManager<T>.validToken({T? rejected})` (single-flight; with `rejected` not identical to the current token it returns the current token without refreshing); `CountingRefresher({Exception? failure})` from Task 3; `InvalidGrant`, `NotAuthenticated` from the core.
- Produces: `final class TokenManagerSocketAuth<T>` with
  - `TokenManagerSocketAuth({required TokenManager<T> manager, required Map<String, Object?> Function(T tokens) payload, Set<int> authCloseCodes = const {4401}})`
  - `Future<Map<String, Object?>> initialPayload()`: validates, remembers the tokens it used, returns `payload(tokens)`; throws what `validToken` throws.
  - `Future<Duration?> onConnectionLost(int? code, String? reason)`: when `code` is in `authCloseCodes` and a payload was built, calls `validToken(rejected: used)` and returns `Duration.zero`; otherwise, or when that throws an `Exception`, returns `null` (the client's default delay). Never throws an `Exception`.
  - Both are used as tear-offs: `initialPayload: auth.initialPayload` matches graphql's `SocketClientConfig.initialPayload` (a function is awaited on every connect), gql_websocket_link's `initialPayload` and graphql-transport-ws `connectionParams` (`FutureOr<Map<String, Object?>?> Function()`); `onConnectionLost: auth.onConnectionLost` matches graphql's `Future<Duration?>? Function(int? code, String? reason)?`. No client package is imported.

- [ ] **Step 1: Write the failing tests**

Create `packages/token_manager_gql/test/token_manager_socket_auth_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

import 'helpers/counting_refresher.dart';

TokenManagerSocketAuth<TokenSet> _socketAuth(
  CountingRefresher refresher, {
  Set<int> authCloseCodes = const {4401},
}) {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(const TokenSet(accessToken: 'old')),
    refresher: refresher,
  );
  return TokenManagerSocketAuth<TokenSet>(
    manager: manager,
    payload: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
    authCloseCodes: authCloseCodes,
  );
}

void main() {
  test('initialPayload is built from valid tokens', () async {
    final auth = _socketAuth(CountingRefresher());

    expect(await auth.initialPayload(), {'Authorization': 'Bearer old'});
  });

  test(
    'an auth close code refreshes the tokens and reconnects at once',
    () async {
      final refresher = CountingRefresher();
      final auth = _socketAuth(refresher);
      await auth.initialPayload();

      expect(await auth.onConnectionLost(4401, 'Unauthorized'), Duration.zero);
      expect(refresher.calls, 1);
      expect(await auth.initialPayload(), {'Authorization': 'Bearer fresh-1'});
    },
  );

  test(
    'another close code keeps the default delay and refreshes nothing',
    () async {
      final refresher = CountingRefresher();
      final auth = _socketAuth(refresher);
      await auth.initialPayload();

      expect(await auth.onConnectionLost(1006, null), isNull);
      expect(refresher.calls, 0);
    },
  );

  test('two auth closes in a row refresh once', () async {
    final refresher = CountingRefresher();
    final auth = _socketAuth(refresher);
    await auth.initialPayload();

    await auth.onConnectionLost(4401, null);
    expect(await auth.onConnectionLost(4401, null), Duration.zero);
    expect(refresher.calls, 1);
  });

  test('a close before any connection refreshes nothing', () async {
    final refresher = CountingRefresher();
    final auth = _socketAuth(refresher);

    expect(await auth.onConnectionLost(4401, null), isNull);
    expect(refresher.calls, 0);
  });

  test('the auth close codes are configurable', () async {
    final refresher = CountingRefresher();
    final auth = _socketAuth(refresher, authCloseCodes: {4001});
    await auth.initialPayload();

    expect(await auth.onConnectionLost(4401, null), isNull);
    expect(await auth.onConnectionLost(4001, null), Duration.zero);
    expect(refresher.calls, 1);
  });

  test(
    'a failed refresh keeps the default delay instead of throwing',
    () async {
      final auth = _socketAuth(
        CountingRefresher(failure: const InvalidGrant()),
      );
      await auth.initialPayload();

      expect(await auth.onConnectionLost(4401, null), isNull);
    },
  );

  test(
    'initialPayload fails with NotAuthenticated once the session ended',
    () async {
      final auth = _socketAuth(
        CountingRefresher(failure: const InvalidGrant()),
      );
      await auth.initialPayload();
      await auth.onConnectionLost(4401, null);

      await expectLater(
        auth.initialPayload(),
        throwsA(isA<NotAuthenticated>()),
      );
    },
  );
}
```

The last test pins the documented behaviour behind graphql's reconnect loop: after `InvalidGrant` the manager signs out, and every later `initialPayload` throws `NotAuthenticated`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/token_manager_gql && dart test test/token_manager_socket_auth_test.dart`
Expected: FAIL to compile: `Type 'TokenManagerSocketAuth' not found`.

- [ ] **Step 3: Implement the helper**

Create `packages/token_manager_gql/lib/src/token_manager_socket_auth.dart`:

```dart
import 'package:token_manager/token_manager.dart';

/// Supplies tokens to a GraphQL WebSocket client and refreshes them when the
/// server closes the socket for an auth reason.
///
/// It knows no client: pass [initialPayload] as the `initialPayload` (or
/// `connectionParams`) callback and [onConnectionLost] as the
/// `onConnectionLost` callback of the client's config. The app still has to
/// reconnect when tokens expire on a live socket, close the socket on logout,
/// and stop the client from retrying while the user is signed out.
final class TokenManagerSocketAuth<T> {
  /// Creates the callbacks for [manager]; [payload] builds the connection
  /// payload from the tokens, and a close code in [authCloseCodes] means the
  /// server rejected them.
  TokenManagerSocketAuth({
    required TokenManager<T> manager,
    required Map<String, Object?> Function(T tokens) payload,
    Set<int> authCloseCodes = const {4401},
  }) : _manager = manager,
       _payload = payload,
       _authCloseCodes = authCloseCodes;

  final TokenManager<T> _manager;
  final Map<String, Object?> Function(T tokens) _payload;
  final Set<int> _authCloseCodes;

  /// The tokens of the last payload, which the open socket was authorised
  /// with.
  T? _used;

  /// Returns the connection payload built from valid tokens.
  ///
  /// Throws what `validToken` throws: `NotAuthenticated`, `InvalidGrant` or
  /// `Transient`.
  Future<Map<String, Object?>> initialPayload() async {
    final tokens = await _manager.validToken();
    _used = tokens;
    return _payload(tokens);
  }

  /// Refreshes the tokens when [code] is an auth close code and returns the
  /// delay before the client reconnects.
  ///
  /// Returns [Duration.zero] after a refresh so the client reconnects at
  /// once, and `null` (the client's default delay) for any other close or when
  /// the refresh fails. It never throws an [Exception]: the client calls it
  /// from a reconnect loop that does not handle errors.
  Future<Duration?> onConnectionLost(int? code, String? reason) async {
    final used = _used;
    if (used == null || !_authCloseCodes.contains(code)) {
      return null;
    }
    try {
      await _manager.validToken(rejected: used);
      return Duration.zero;
    } on Exception catch (_) {
      // `initialPayload` reports the failure on the next connect.
      return null;
    }
  }
}
```

`4401` is the graphql-ws close code for Unauthorized; the graphql README example uses `4001`. The default stays `{4401}` and the README tells apps to set their server's code.

- [ ] **Step 4: Export and record it**

Replace `packages/token_manager_gql/lib/token_manager_gql.dart` with:

```dart
/// A gql_link `Link` that attaches token_manager tokens to GraphQL requests
/// and replays a request once after an auth failure.
library;

export 'src/auth_failure_matcher.dart' show AuthFailureMatcher;
export 'src/skip_authorization.dart' show SkipAuthorization;
export 'src/token_manager_link.dart' show TokenManagerLink;
export 'src/token_manager_socket_auth.dart' show TokenManagerSocketAuth;
```

Append to `packages/token_manager_gql/CHANGELOG.md` under `### Added`:

```markdown
- `TokenManagerSocketAuth<T>`, the `initialPayload` and `onConnectionLost`
  callbacks for GraphQL WebSocket clients.
```

- [ ] **Step 5: Run all tests to verify they pass**

Run: `cd packages/token_manager_gql && dart test`
Expected: PASS (44 tests).

- [ ] **Step 6: Format and analyze**

Run: `dart format packages && dart format packages && dart analyze packages`
Expected: second format run `0 changed`; `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add packages/token_manager_gql
git commit -m "feat(token_manager_gql): add TokenManagerSocketAuth for WebSocket clients

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: README, example and publish check

**Files:**
- Create: `packages/token_manager_gql/example/main.dart`
- Create: `packages/token_manager_gql/README.md`

**Interfaces:**
- Consumes: every public type from Tasks 2-5: `AuthFailureMatcher`, `SkipAuthorization`, `TokenManagerLink<T>`, `TokenManagerSocketAuth<T>`.
- Produces: a runnable example and a README that documents the chain order, both failure channels, the `data == null` rule, anonymous operations, error types, the WebSocket helper and what stays the app's job, and the dependency constraints.

- [ ] **Step 1: Write the example**

Create `packages/token_manager_gql/example/main.dart`:

```dart
import 'dart:io';

import 'package:gql/language.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

final class _ExampleRefresher implements TokenRefresher<TokenSet> {
  const _ExampleRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async =>
      const TokenSet(accessToken: 'fresh');
}

/// Stands in for `HttpLink`: it answers HTTP 401 to every token but `fresh`.
final class _FakeServer extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final headers = request.context.entry<HttpLinkHeaders>()?.headers;
    if (headers?['Authorization'] != 'Bearer fresh') {
      return Stream.error(const ServerException(statusCode: 401));
    }
    return Stream.value(const Response(data: {'me': 'ada'}, response: {}));
  }
}

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(const TokenSet(accessToken: 'stale')),
    refresher: const _ExampleRefresher(),
  );

  // In an app the chain is
  // Link.from([DedupeLink(), TokenManagerLink(...), HttpLink(uri)]).
  final link = Link.from([
    TokenManagerLink<TokenSet>(
      manager: manager,
      headers: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
    ),
    _FakeServer(),
  ]);

  final request = Request(
    operation: Operation(document: parseString('query Me { me }')),
  );
  final response = await link.request(request).first;
  stdout.writeln('Data after one refresh and replay: ${response.data}');

  await manager.dispose();
}
```

- [ ] **Step 2: Run the example**

Run: `cd packages/token_manager_gql && dart run example/main.dart`
Expected: prints `Data after one refresh and replay: {me: ada}`.

- [ ] **Step 3: Write the README**

Create `packages/token_manager_gql/README.md` with exactly this content (code samples that need `gql_http_link`, `gql_dedupe_link` or `graphql` are app code, not package code):

````markdown
# token_manager_gql

[![Pub Version](https://img.shields.io/pub/v/token_manager_gql.svg)](https://pub.dev/packages/token_manager_gql)

A [`gql_link`](https://pub.dev/packages/gql_link) `Link` that attaches the
tokens of a [`token_manager`](https://pub.dev/packages/token_manager)
`TokenManager` to GraphQL requests and replays a request once after the server
rejects them. It works with every client built on `gql_link`, such as
`graphql`, `graphql_flutter` and `ferry`, and depends only on `gql_link`,
`gql_exec` and `token_manager`.

## Installation

```yaml
dependencies:
  token_manager: ^0.1.0
  token_manager_gql: ^0.1.0
```

## Usage

```dart
import 'package:gql_dedupe_link/gql_dedupe_link.dart';
import 'package:gql_http_link/gql_http_link.dart';
import 'package:gql_link/gql_link.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

Link buildLink(TokenManager<TokenSet> manager) => Link.from([
  DedupeLink(),
  TokenManagerLink<TokenSet>(
    manager: manager,
    headers: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
  ),
  HttpLink('https://api.example.com/graphql'),
]);
```

Pass the link to your client: `GraphQLClient(link: link, cache: ...)` for
`graphql` and `graphql_flutter`, `Client(link: link)` for `ferry`.

A runnable version without a network is in [example/main.dart](example/main.dart).

### Where the link goes

- **`DedupeLink` → `TokenManagerLink` → `HttpLink`.** After `DedupeLink`,
  identical requests share one send and one replay. Before it, every request
  carries its own header and deduplication stops working.
- **Never together with graphql's `AuthLink`.** Both would set the header,
  and `AuthLink` cannot replay.
- **`ErrorLink` goes before `TokenManagerLink`**, never between it and
  `HttpLink`, or it would handle the 401 before this link sees it.
- **Subscriptions bypass it.** A WebSocket link ignores `HttpLinkHeaders`, so
  split subscriptions off before this link and authorise the socket with
  `TokenManagerSocketAuth` (see below):

  ```dart
  Link.split(
    (request) =>
        request.operation.getOperationType() == OperationType.subscription,
    webSocketLink,
    Link.from([DedupeLink(), tokenLink, httpLink]),
  );
  ```

  `DedupeLink` dedupes every operation except mutations by default; pass
  `shouldDedupe` if subscriptions also go through it.

## How a rejection is recognised

A server rejects tokens on one of two channels, and `AuthFailureMatcher`
recognises both:

| Channel | Default rule |
|---|---|
| An error event, such as `HttpLink`'s `HttpLinkServerException` | a `ServerException` whose `statusCode` is 401 |
| A response whose `errors` carry an auth code (often an HTTP 200) | `errors[].extensions.code` is `UNAUTHENTICATED` |

Set other codes with
`AuthFailureMatcher(statusCodes: {401, 419}, errorCodes: {'invalid-jwt'})`.

A rejected **response is replayed only when its `data` is null**. A response
with data may come from a mutation that already ran, so it is delivered as is.
Only a rejection before the first response is replayed, and only once. When
the replay is rejected too, its error or response reaches the client
unchanged.

`HttpLink` parses the body before it checks the status, so a 401 whose body is
not GraphQL JSON (empty, HTML) arrives as an `HttpLinkParserException`, which
has no status code. To replay it, extend the matcher in your app, which
already depends on `gql_http_link`:

```dart
final class AppAuthFailureMatcher extends AuthFailureMatcher {
  const AppAuthFailureMatcher();

  @override
  bool isAuthError(Object error) =>
      (error is HttpLinkParserException && error.response.statusCode == 401) ||
      super.isAuthError(error);
}
```

## Operations without tokens

A login or sign-up runs before tokens exist. Mark it with `SkipAuthorization`
and the link forwards it unchanged, without asking the manager:

```dart
// gql_link
final login = request.withContextEntry(const SkipAuthorization());

// graphql
MutationOptions(
  document: loginMutation,
  context: Context().withEntry(const SkipAuthorization()),
);
```

Without the marker, a request sent while signed out fails with
`NotAuthenticated`.

## Errors

The link never refreshes by itself: it asks the manager for valid tokens and
reports the tokens a server rejected. The manager's failures reach the client
as error events: `NotAuthenticated` (no session), `InvalidGrant` (the session
ended and the manager signed out) and `Transient` (the refresh may succeed
later; the session stays). They are not `LinkException`s. Listen to
`manager.states` to send the user to sign-in on `Unauthenticated`.

## Subscriptions

`TokenManagerSocketAuth` supplies tokens to a WebSocket client without
depending on one:

```dart
final socketAuth = TokenManagerSocketAuth<TokenSet>(
  manager: manager,
  payload: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
  authCloseCodes: {4401}, // what your server sends when it rejects the tokens
);

// graphql / graphql_flutter
final webSocketLink = WebSocketLink(
  'wss://api.example.com/graphql',
  config: SocketClientConfig(
    initialPayload: socketAuth.initialPayload,
    onConnectionLost: socketAuth.onConnectionLost,
  ),
);
```

`initialPayload` asks for valid tokens on every connect. `onConnectionLost`
refreshes the tokens when the server closes the socket with one of
`authCloseCodes` and asks the client to reconnect at once. With
`gql_websocket_link`, pass `initialPayload` (or the graphql-transport-ws
client's `connectionParams`) the same way.

What stays the app's job:

- **Tokens that expire on a live socket.** The server checks them when the
  socket connects. Unless it closes the socket with an auth code, nothing
  happens; reconnect yourself when `manager.states` emits new tokens if your
  server requires it.
- **Logout.** Close or dispose the WebSocket link when `manager.states` emits
  `Unauthenticated`.
- **The reconnect loop after the session ended.** graphql's socket client
  catches the error `initialPayload` throws (`InvalidGrant`, then
  `NotAuthenticated`) and tries again every `delayBetweenReconnectionAttempts`
  (5 seconds by default), forever. Dispose the link, or set
  `autoReconnect: false`, when the user is signed out.
- **Close codes.** WebSockets have no standard auth code: graphql-ws uses 4401,
  the graphql README uses 4001. Set `authCloseCodes` to what your server sends.
- **Duplicate events.** A resubscription after a reconnect may repeat events;
  only the app knows whether that is safe.

## Dependency constraints

`gql_exec` 1.1.0 is retracted, and `gql_link` 1.1.0 requires `gql_exec ^1.1.0`.
This package therefore accepts `gql_link ^1.0.0` and `gql_exec ^1.0.0`, which
resolve to the stable `gql_link` 1.0.0+1 and `gql_exec` 1.0.0+1 (their API is
the same as 1.1.0) and match what `graphql` 5.x and `ferry` require.
````

Facts behind the README, checked while writing this plan: graphql 5's `BaseOptions` takes `Context? context` ("Context to be passed to link execution chain"); graphql's `SocketClientConfig.onConnectionLost` is `Future<Duration?>? Function(int? code, String? reason)?` and its result replaces `delayBetweenReconnectionAttempts` (default 5 seconds); `SocketClient._connect` awaits a function `initialPayload` on every (re)connect and routes its exceptions into `onConnectionLost`; `DedupeLink({bool Function(Request) shouldDedupe})` dedupes everything but mutations by default.

- [ ] **Step 4: Run the publish check**

Run: `cd packages/token_manager_gql && dart pub publish --dry-run`
Expected: `Package has 0 warnings.` (A warning about uncommitted files means Step 5 must run first; commit, then rerun.)

- [ ] **Step 5: Run the whole workspace gate**

Run, from the repository root:

```bash
dart pub get
dart format packages && dart format packages
dart analyze packages
(cd packages/token_manager && dart test)
(cd packages/token_manager_gql && dart test)
```

Expected: the second format run `0 changed`; `No issues found!`; both test runs pass (44 tests in `token_manager_gql`).

- [ ] **Step 6: Commit**

```bash
git add packages/token_manager_gql
git commit -m "docs(token_manager_gql): add the README and a runnable example

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Then rerun Step 4 and confirm `Package has 0 warnings.`

---

## Note: CI needs (do not edit `.github/workflows/ci.yml` on this branch)

Other adapter branches change `ci.yml` concurrently, so the CI change is made when the branches are merged. `token_manager_gql` needs, in the `analyze-test` job of `.github/workflows/ci.yml`:

```yaml
      - name: Test token_manager_gql
        working-directory: packages/token_manager_gql
        run: dart test
```

Format and analyze already cover it (they run on `packages`). If a `publish-dry-run` job lists packages, add `packages/token_manager_gql`. If CI ever runs `dart pub downgrade`, the floor resolves to `gql_link 1.0.0` / `gql_exec 1.0.0` / `gql 1.0.0`, which `dart pub downgrade` was checked to accept.

## Open questions (not blocking the tasks)

1. **Core constraint.** `authorizeStream` exists only in the core's unreleased `0.2.0` (its CHANGELOG), while the core's pubspec still says `0.1.0`, so this package depends on `token_manager: ^0.1.0` to resolve in the workspace. When the core's version becomes `0.2.0`, this constraint must become `^0.2.0` in the same change, or the published package would accept a core without `authorizeStream`.
2. **Manager failures are not `LinkException`s.** `NotAuthenticated`, `InvalidGrant` and `Transient` reach the client unwrapped (documented in the README). Wrapping them in a `LinkException` subclass would make `ErrorLink.onException` see them; that would be a new public type, deferred.
3. **Default WebSocket close code.** `{4401}` (graphql-ws) was chosen over `4001` (graphql README example). Apps set their own.
4. **Spec naming.** The spec still says `token_manager_gql_link` / `GqlTokenLink` and "queries and mutations use `authorize`"; update section 4 and 6 of the spec when this lands.
