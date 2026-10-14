# token_manager_dio 0.2 rewrite: implementation plan (phase 3, adapter 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `RefreshInterceptor<T>` in `packages/token_manager_dio` on the new `token_manager` core (`validToken`, `validToken(rejected:)`), so a request is authorised through the manager, replayed exactly once after an auth failure, and never loops; ship it as `token_manager_dio` 0.2.0 with tests on a fake `HttpClientAdapter`.

**Architecture:** The interceptor stays a plain `Interceptor` (not queued). `onRequest` asks `manager.validToken()`, applies the header through the delegate and remembers the tokens it used in `RequestOptions.extra`. On an auth failure (`delegate.shouldRefresh`) in `onError` or `onResponse` it calls `manager.validToken(rejected: used)`; if the answer is the same instance it passes the original failure on, otherwise it sends one marked copy of the request through the supplied `Dio`. The marker (`extra`) makes `onRequest` and the failure handlers skip a replay, so it can never loop, even when the user passes the `Dio` that owns the interceptor. The small helper `RequestMarks<T>` owns the `extra` keys and the request copy; the interceptor never refreshes by itself.

**Tech Stack:** Dart 3.10, `dio` (`>=5.2.0 <6.0.0`, tested against 5.11.1), `package:test`, the `token_manager` core of this workspace.

**Spec:** `docs/superpowers/specs/2026-10-14-token-manager-redesign-design.md` (section 3 principles, section 6 "dio" bullet, roadmap phase 3 item 1). Read `CLAUDE.md` as well.

## Global Constraints

- Work on branch `feat/token-manager-dio-0.2` (already created from `main`); never commit to `main`. Change only `packages/token_manager_dio/` and this plan; do not edit `packages/token_manager/`, `packages/token_manager_grpc/`, `.github/workflows/ci.yml` or the root `README.md` (other adapters are planned on other branches).
- Every commit uses Conventional Commits with a package scope and ends with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Minimum SDK `^3.10.0`; the package keeps `resolution: workspace`; no `pubspec_overrides.yaml`.
- Public names stay: `RefreshInterceptor<T>` (constructor `manager`, `delegate`, optional `dio`) and `RefreshInterceptorDelegate<T>` (`applyTokensToRequest(RequestOptions, T?)`, `shouldRefresh(Response?)`). Existing subclasses must compile unchanged.
- The adapter depends only on the core and `dio`. The core knows nothing about HTTP; the adapter attaches the header, recognises an auth failure and replays once. It never refreshes by itself: refresh is `validToken` / `validToken(rejected:)`.
- Mutations are replayed only when the failure is the transport-level auth failure (`shouldRefresh`); there is no other trigger.
- Code rules: object-oriented, no top-level functions except `main` in `example/` and tests; no `!`, no `dynamic` (an inferred `dynamic` with a comment is the only exception, see Task 3); `catch` always has an `on` clause and `Error` is never caught; `late` needs a comment; `///` docs with one summary sentence and `[brackets]`; never add `// ignore:` without a reason.
- Size limits: lib file 300 lines, test file 500, method 40, parameters 5, nesting 3, about 15 members per class, one public class per file, no `utils`/`helpers`/`common` in `lib/`, no `part`.
- At the end of every task `dart format --output=none --set-exit-if-changed packages` exits 0 (run `dart format packages` first), `dart analyze packages` prints `No issues found!`, and `cd packages/token_manager_dio && dart test` passes.
- Tests ship in the same commit as the code; no network (the fake adapter answers); one behaviour per test; test set-up longer than about five lines is a helper.
- Public API changes need a `CHANGELOG.md` entry; before 1.0 a breaking change is a minor bump, and only this package is bumped (to 0.2.0).
- All code, comments and docs are in English.

## Review Focus

Inputs the spec implies but a happy-path 401-then-200 test would not exercise. Each has a pinning test in the task named in brackets.

1. The server keeps answering 401, with the interceptor's own `Dio` passed as `dio` (the 0.1 infinite loop) and with a separate `Dio`: exactly two requests and one refresh, then the 401 reaches the caller. [Task 3]
2. A request body that cannot be sent twice: a `Stream` body is not replayed and triggers no refresh; a `FormData` body is cloned (its first send finalized it). [Task 5]
3. A response type other than JSON: `Dio.fetch<Object?>` silently resets the request to JSON, so a plain-text body that is not JSON would fail on the replay; the replay must keep the original type. [Task 5]
4. The session changed while the request was in flight: a late 401 for a token that is no longer current must replay with the current token without a second refresh, and after a logout must surface `NotAuthenticated`. [Task 5]
5. The refresh itself fails: `InvalidGrant` (session ends) and `Transient` (session kept) must reach the caller as `DioException.error` with the original 401 response attached, never as a hang or a silent replay with stale tokens. [Task 5]

## File structure

Modified in `packages/token_manager_dio/`:

- `pubspec.yaml`: `test` dev dependency (Task 1); version `0.2.0` and the core constraint (Task 6).
- `lib/src/refresh_interceptor.dart`: rewritten (Tasks 3, 4), about 140 lines.
- `lib/src/refresh_interceptor_delegate.dart`: doc comments only (Task 4).
- `lib/token_manager_dio.dart`: barrel with `show` clauses (Task 3).
- `example/main.dart`, `README.md`, `CHANGELOG.md`: Task 6.

Created in `packages/token_manager_dio/`:

- `lib/src/request_marks.dart`: `RequestMarks<T>`, the `extra` keys, the replay copy (Task 2).
- `test/quality/size_limits_test.dart`, `test/helpers/size_limits.dart`: the size ratchet, copied from `packages/token_manager` (Task 1).
- `test/helpers/fake_http_adapter.dart`, `fake_refresher.dart`, `bearer_delegate.dart`, `dio_errors.dart`, `dio_fixture.dart`: shared fakes (Task 3).
- `test/request_marks_test.dart` (Task 2), `test/refresh_interceptor_test.dart` (Task 3), `test/refresh_interceptor_delegate_test.dart` and `test/refresh_interceptor_response_test.dart` (Task 4), `test/refresh_interceptor_request_test.dart` and `test/refresh_interceptor_failure_test.dart` (Task 5).

Decisions recorded here:

- **Ratchet: yes.** `CLAUDE.md` says the limits are enforced per package by `test/quality/size_limits_test.dart`, and the package now has a `test/` tree. The two files are copied verbatim (the helper uses only `dart:io`); the allowlists start empty. The copy is 474 lines (limit 500); the duplication across adapters is accepted for now, since a package cannot import another package's `test/`.
- **Names stay.** The spec names the new class `DioTokenInterceptor` with a deprecated `RefreshInterceptor` subclass and `applyTo`. The ruling for this plan is source compatibility with the 0.1 names, so neither `DioTokenInterceptor` nor `applyTo` is introduced here.
- **Replay client.** The 0.1 `dio ?? Dio()` default stays, with a doc line telling users to pass the `Dio` the interceptor is added to. Replay uses `Dio.fetch(RequestOptions)`, which never touches `dio.options`, so the 0.1 `baseUrl` mutation is gone.
- **Failures become `DioException`s.** A failure to obtain or renew tokens is wrapped in a `DioException` whose `error` is the original exception (`NotAuthenticated`, `InvalidGrant`, `Transient`, or a store error); on the replay path the 401 `response` is attached. Callers branch on `e.error`.
- **Workspace resolution of the core constraint** (verified): a workspace package is resolved by name and its own `version` must satisfy every dependent's constraint. The core `pubspec.yaml` is still `0.1.0` (its CHANGELOG already says `0.2.0 - Unreleased`) and `token_manager_grpc` depends on `^0.1.0`, so `token_manager: ^0.2.0` here makes `dart pub get` fail ("version solving failed"), and bumping the core to `0.2.0` would break `token_manager_grpc` the same way. This plan therefore keeps the dependency at whatever the workspace allows (Task 1 step 1 decides) and leaves the one coordinated bump to the release (see "Release handoff" at the end).

---

### Task 1: Test dependency and size ratchet

**Files:**
- Modify: `packages/token_manager_dio/pubspec.yaml`
- Create: `packages/token_manager_dio/test/quality/size_limits_test.dart` (copy)
- Create: `packages/token_manager_dio/test/helpers/size_limits.dart` (copy)

**Interfaces:**
- Consumes: nothing.
- Produces: a package that runs `dart test` and enforces the size limits for `lib/` and `test/`.

- [ ] **Step 1: Decide the core constraint**

Run from the repository root:

```bash
git switch feat/token-manager-dio-0.2
grep -n '^version' packages/token_manager/pubspec.yaml
grep -n 'token_manager:' packages/token_manager_grpc/pubspec.yaml packages/token_manager_dio/pubspec.yaml
```

Expected today: core `version: 0.1.0`, both adapters `token_manager: ^0.1.0`. In that case leave the constraint in `packages/token_manager_dio/pubspec.yaml` at `^0.1.0` for this branch. Only if the core already says `0.2.0` and `token_manager_grpc` already depends on `^0.2.0` (after a rebase on a `main` that carries the coordinated bump), change this package's constraint to `token_manager: ^0.2.0`. Either way finish with `dart pub get` printing no error. Do not edit the core or grpc pubspecs.

- [ ] **Step 2: Add the test dependency**

Append to `packages/token_manager_dio/pubspec.yaml` (after the `dependencies:` block, same style as the core's pubspec):

```yaml

dev_dependencies:
  test: ^1.31.0
```

- [ ] **Step 3: Copy the ratchet**

```bash
mkdir -p packages/token_manager_dio/test/quality packages/token_manager_dio/test/helpers
cp packages/token_manager/test/quality/size_limits_test.dart packages/token_manager_dio/test/quality/size_limits_test.dart
cp packages/token_manager/test/helpers/size_limits.dart packages/token_manager_dio/test/helpers/size_limits.dart
```

Both allowlists in the copied test (`_fileAllowlist`, `_permanent`, `_methodAllowlist`) stay empty. Do not edit the copies.

- [ ] **Step 4: Run the tests**

Run: `dart pub get && cd packages/token_manager_dio && dart test`
Expected: PASS, 2 tests (the two ratchet tests). If the ratchet reports a file of the old interceptor over a limit, report it instead of adding an allowlist entry: the old files are 146 and 19 lines, so none is expected.

- [ ] **Step 5: Gate and commit**

```bash
dart format packages && dart analyze packages
git add packages/token_manager_dio/pubspec.yaml packages/token_manager_dio/test
git commit -m "build(token_manager_dio): add the test dependency and the size ratchet

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected from `dart analyze packages`: `No issues found!`.

---

### Task 2: RequestMarks: the extra keys and the replay copy

**Files:**
- Create: `packages/token_manager_dio/lib/src/request_marks.dart`
- Test: `packages/token_manager_dio/test/request_marks_test.dart`

**Interfaces:**
- Consumes: `dio` types only.
- Produces (used by Tasks 3 and 4), in `package:token_manager_dio/src/request_marks.dart`:

```dart
final class RequestMarks<T> {
  const RequestMarks();
  static const String tokensKey = 'token_manager_dio.tokens';
  static const String replayedKey = 'token_manager_dio.replayed';
  T? tokensOf(RequestOptions options);
  void recordTokens(RequestOptions options, T tokens);
  bool isReplay(RequestOptions options);
  bool canReplay(RequestOptions options);
  RequestOptions replayOf(RequestOptions options, T tokens);
}
```

Note for the implementer: never write `const RequestMarks()` where the type argument is a type variable (the interceptor's `T`): a const expression infers `RequestMarks<Never>` and every `recordTokens` call then throws a cast error. The interceptor uses `RequestMarks<T>()`.

- [ ] **Step 1: Write the failing test**

Create `packages/token_manager_dio/test/request_marks_test.dart`:

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:token_manager_dio/src/request_marks.dart';

void main() {
  const marks = RequestMarks<String>();

  RequestOptions request({Object? data}) {
    return RequestOptions(path: '/me', data: data);
  }

  test('knows no tokens for a request it did not mark', () {
    expect(marks.tokensOf(request()), isNull);
  });

  test('returns the tokens it recorded', () {
    final options = request();

    marks.recordTokens(options, 'old');

    expect(marks.tokensOf(options), 'old');
  });

  test('a recorded request is not a replay', () {
    final options = request();

    marks.recordTokens(options, 'old');

    expect(marks.isReplay(options), isFalse);
  });

  test('a stream body cannot be replayed', () {
    final options = request(data: Stream.value(utf8.encode('x')));

    expect(marks.canReplay(options), isFalse);
  });

  test('text, JSON and FormData bodies can be replayed', () {
    expect(marks.canReplay(request(data: 'x')), isTrue);
    expect(marks.canReplay(request(data: {'a': 1})), isTrue);
    expect(marks.canReplay(request(data: FormData())), isTrue);
  });

  group('the replay copy', () {
    test('is marked and carries the new tokens', () {
      final options = request()..extra['keep'] = 1;
      marks.recordTokens(options, 'old');

      final replay = marks.replayOf(options, 'new');

      expect(marks.isReplay(replay), isTrue);
      expect(marks.tokensOf(replay), 'new');
      expect(replay.extra['keep'], 1);
    });

    test('leaves the original request untouched', () {
      final options = request();
      marks.recordTokens(options, 'old');

      marks.replayOf(options, 'new');

      expect(marks.isReplay(options), isFalse);
      expect(marks.tokensOf(options), 'old');
    });

    test('clones a FormData body', () {
      final form = FormData.fromMap({'title': 'hello'});

      final replay = marks.replayOf(request(data: form), 'new');

      expect(replay.data, isA<FormData>());
      expect(replay.data, isNot(same(form)));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/token_manager_dio && dart test test/request_marks_test.dart`
Expected: FAIL to compile, `Target of URI doesn't exist: 'package:token_manager_dio/src/request_marks.dart'`.

- [ ] **Step 3: Write the implementation**

Create `packages/token_manager_dio/lib/src/request_marks.dart`:

```dart
import 'package:dio/dio.dart';

/// Reads and writes what the interceptor keeps in [RequestOptions.extra].
final class RequestMarks<T> {
  /// Creates the helper.
  const RequestMarks();

  /// The `extra` key that holds the tokens a request was sent with.
  static const String tokensKey = 'token_manager_dio.tokens';

  /// The `extra` key that is `true` on the one replay of a request.
  static const String replayedKey = 'token_manager_dio.replayed';

  /// Returns the tokens [options] was sent with, or `null` when unknown.
  T? tokensOf(RequestOptions options) {
    return switch (options.extra[tokensKey]) {
      final T tokens => tokens,
      _ => null,
    };
  }

  /// Remembers that [options] is sent with [tokens].
  void recordTokens(RequestOptions options, T tokens) {
    options.extra[tokensKey] = tokens;
  }

  /// Whether [options] is the replay of an earlier request.
  bool isReplay(RequestOptions options) => options.extra[replayedKey] == true;

  /// Whether [options] can be sent a second time.
  ///
  /// A stream body is consumed by the first attempt.
  bool canReplay(RequestOptions options) => options.data is! Stream<Object?>;

  /// Returns the copy of [options] that is sent again with [tokens].
  ///
  /// The copy is marked as a replay, so it is never replayed itself. A
  /// [FormData] body is cloned because the first attempt finalized it.
  RequestOptions replayOf(RequestOptions options, T tokens) {
    return options.copyWith(
      data: switch (options.data) {
        FormData(:final clone) => clone(),
        final Object? data => data,
      },
      extra: {...options.extra, tokensKey: tokens, replayedKey: true},
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/token_manager_dio && dart test test/request_marks_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Gate and commit**

```bash
dart format packages && dart analyze packages
git add packages/token_manager_dio/lib/src/request_marks.dart packages/token_manager_dio/test/request_marks_test.dart
git commit -m "feat(token_manager_dio): mark replayed requests

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected from `dart analyze packages`: `No issues found!` (the class is not used by the interceptor until Task 3; if the analyzer reports it as unused, say so in the task report rather than adding an ignore).

---

### Task 3: The interceptor on the new core: header, NotAuthenticated, one replay

**Files:**
- Create: `packages/token_manager_dio/test/helpers/fake_http_adapter.dart`
- Create: `packages/token_manager_dio/test/helpers/fake_refresher.dart`
- Create: `packages/token_manager_dio/test/helpers/bearer_delegate.dart`
- Create: `packages/token_manager_dio/test/helpers/dio_errors.dart`
- Create: `packages/token_manager_dio/test/helpers/dio_fixture.dart`
- Create: `packages/token_manager_dio/test/refresh_interceptor_test.dart`
- Modify (replace): `packages/token_manager_dio/lib/src/refresh_interceptor.dart`
- Modify (replace): `packages/token_manager_dio/lib/token_manager_dio.dart`

**Interfaces:**
- Consumes: `RequestMarks<T>` (Task 2); from the core `TokenManager<T>.validToken({T? rejected})`, `NotAuthenticated`, `TokenSet`, `InMemoryTokenStore<T>`, `TokenRefresher<T>`, `RefreshFailure`, `InvalidGrant`, `Transient`.
- Produces: the final public `RefreshInterceptor<T>` (constructor `{required TokenManager<T> manager, required RefreshInterceptorDelegate<T> delegate, Dio? dio}`) handling `onRequest` and `onError`; Task 4 adds `onResponse`. Test helpers used by Tasks 4 and 5:
  - `DioFixture({bool signedIn = true, bool withRefresher = true, RefreshFailure? refreshFailure, bool ownDio = true, String accepted = 'Bearer new', RefreshInterceptorDelegate<TokenSet> delegate = const BearerDelegate()})` with fields `adapter`, `refresher`, `manager`, `dio`, `replayDio` and `static const TokenSet initial` (`old` / `refresh-1`). The session starts with `old`; the fake server answers 200 only to the `Authorization` value `accepted`, else 401.
  - `FakeHttpAdapter` with `requests` (`List<RecordedRequest>`: `uri`, `authorization`, `body`), `gate` (`Completer<void>?`) and `successBody`.
  - `FakeRefresher` with `calls`; it returns `TokenSet(accessToken: 'new', refreshToken: 'refresh-2')` or throws its `failure`.
  - `DioErrors` with `wrapping(Matcher error, {int? status})` and `withStatus(int status)`.

- [ ] **Step 1: Write the test helpers**

Create `packages/token_manager_dio/test/helpers/fake_http_adapter.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One request the adapter saw.
final class RecordedRequest {
  /// Creates a record.
  const RecordedRequest({
    required this.uri,
    required this.authorization,
    required this.body,
  });

  /// The full address.
  final Uri uri;

  /// The `Authorization` header, or `null` when there was none.
  final String? authorization;

  /// The request body as text; empty when there was none.
  final String body;
}

/// An adapter that answers 200 to one `Authorization` value and 401 to all
/// others, and records every request. No network is used.
final class FakeHttpAdapter implements HttpClientAdapter {
  /// Creates an adapter that accepts only [accepted].
  FakeHttpAdapter({required this.accepted, this.successBody = '{"ok":true}'});

  /// The only `Authorization` value that gets a 200.
  final String accepted;

  /// The body of a 200 answer.
  String successBody;

  /// Every request in arrival order.
  final List<RecordedRequest> requests = [];

  /// When set, an answer waits until it completes.
  Completer<void>? gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final chunks = await requestStream?.toList() ?? const <Uint8List>[];
    final authorization = options.headers['Authorization'];
    requests.add(
      RecordedRequest(
        uri: options.uri,
        authorization: authorization is String ? authorization : null,
        body: utf8.decode(chunks.expand((chunk) => chunk).toList()),
      ),
    );
    await gate?.future;
    final ok = authorization == accepted;
    return ResponseBody.fromString(
      ok ? successBody : '',
      ok ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
```

Create `packages/token_manager_dio/test/helpers/fake_refresher.dart`:

```dart
import 'package:token_manager/token_manager.dart';

/// A refresher that counts its calls and returns the `new` access token, or
/// fails with [failure].
final class FakeRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher, optionally failing with [failure].
  FakeRefresher({this.failure});

  /// What every call throws; `null` makes calls succeed.
  final RefreshFailure? failure;

  /// How many times [refresh] was called.
  int calls = 0;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    calls++;
    // Let concurrent requests reach the manager while the refresh runs.
    await Future<void>.delayed(Duration.zero);
    final error = failure;
    if (error != null) {
      throw error;
    }
    return const TokenSet(accessToken: 'new', refreshToken: 'refresh-2');
  }
}
```

Create `packages/token_manager_dio/test/helpers/bearer_delegate.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

/// Sends the access token as a bearer `Authorization` header.
final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  /// Creates the delegate.
  const BearerDelegate();

  @override
  void applyTokensToRequest(RequestOptions options, TokenSet? tokens) {
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
  }
}
```

Create `packages/token_manager_dio/test/helpers/dio_errors.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// Builds matchers for the [DioException] the interceptor throws.
final class DioErrors {
  /// Creates the matcher factory.
  const DioErrors();

  /// Matches a [DioException] whose `error` matches [error].
  ///
  /// When [status] is given, the exception must also carry a response with
  /// that status code.
  Matcher wrapping(Matcher error, {int? status}) {
    final matcher = isA<DioException>().having((e) => e.error, 'error', error);
    return status == null ? matcher : matcher.having(_status, 'status', status);
  }

  /// Matches a [DioException] whose response has the status code [status].
  Matcher withStatus(int status) {
    return isA<DioException>().having(_status, 'status', status);
  }

  int? _status(DioException error) => error.response?.statusCode;
}
```

Create `packages/token_manager_dio/test/helpers/dio_fixture.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

import 'bearer_delegate.dart';
import 'fake_http_adapter.dart';
import 'fake_refresher.dart';

/// A [Dio] with a [RefreshInterceptor], a manager and fakes, wired together.
///
/// The session starts with the access token `old`. Unless `accepted` says
/// otherwise the server accepts only `Bearer new`, so every first attempt gets
/// a 401.
final class DioFixture {
  /// Creates a fixture.
  ///
  /// [signedIn] false starts without tokens, [withRefresher] false builds a
  /// manager that cannot refresh, [refreshFailure] makes refreshes fail,
  /// [accepted] is the one `Authorization` value the server answers 200 to,
  /// [ownDio] false lets the replay go through a separate `Dio`, and
  /// [delegate] replaces the bearer delegate.
  factory DioFixture({
    bool signedIn = true,
    bool withRefresher = true,
    RefreshFailure? refreshFailure,
    bool ownDio = true,
    String accepted = 'Bearer new',
    RefreshInterceptorDelegate<TokenSet> delegate = const BearerDelegate(),
  }) {
    final adapter = FakeHttpAdapter(accepted: accepted);
    final refresher = FakeRefresher(failure: refreshFailure);
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(signedIn ? initial : null),
      refresher: withRefresher ? refresher : null,
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter;
    final replayDio = ownDio ? dio : (Dio()..httpClientAdapter = adapter);
    dio.interceptors.add(
      RefreshInterceptor<TokenSet>(
        manager: manager,
        delegate: delegate,
        dio: replayDio,
      ),
    );
    return DioFixture._(
      adapter: adapter,
      refresher: refresher,
      manager: manager,
      dio: dio,
      replayDio: replayDio,
    );
  }

  DioFixture._({
    required this.adapter,
    required this.refresher,
    required this.manager,
    required this.dio,
    required this.replayDio,
  });

  /// The tokens the session starts with.
  static const TokenSet initial = TokenSet(
    accessToken: 'old',
    refreshToken: 'refresh-1',
  );

  /// The server stand-in.
  final FakeHttpAdapter adapter;

  /// The refresher the manager uses.
  final FakeRefresher refresher;

  /// The manager the interceptor asks for tokens.
  final TokenManager<TokenSet> manager;

  /// The client under test.
  final Dio dio;

  /// The client that sends replays; [dio] itself unless `ownDio` was false.
  final Dio replayDio;
}
```

- [ ] **Step 2: Write the failing tests**

Create `packages/token_manager_dio/test/refresh_interceptor_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/dio_errors.dart';
import 'helpers/dio_fixture.dart';

void main() {
  const errors = DioErrors();

  group('attaching the token', () {
    test('sends the current access token in the delegate header', () async {
      final fixture = DioFixture(accepted: 'Bearer old');

      final response = await fixture.dio.get<Object?>('/me');

      expect(response.statusCode, 200);
      expect(fixture.adapter.requests.single.authorization, 'Bearer old');
    });

    test('fails with NotAuthenticated when logged out', () async {
      final fixture = DioFixture(signedIn: false);

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(
        call,
        throwsA(errors.wrapping(isA<NotAuthenticated>())),
      );
      expect(fixture.adapter.requests, isEmpty);
    });
  });

  group('replaying after a 401', () {
    test('sends the request again once with the refreshed token', () async {
      final fixture = DioFixture();

      final response = await fixture.dio.get<Object?>('/me');

      expect(response.statusCode, 200);
      expect(fixture.adapter.requests.map((r) => r.authorization), [
        'Bearer old',
        'Bearer new',
      ]);
      expect(fixture.refresher.calls, 1);
    });

    test('replays exactly once when the server keeps answering 401', () async {
      final fixture = DioFixture(accepted: 'Bearer never');

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(call, throwsA(errors.withStatus(401)));
      expect(fixture.adapter.requests, hasLength(2));
      expect(fixture.refresher.calls, 1);
    });

    test('replays exactly once through a separate Dio as well', () async {
      final fixture = DioFixture(accepted: 'Bearer never', ownDio: false);

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(call, throwsA(errors.withStatus(401)));
      expect(fixture.adapter.requests, hasLength(2));
    });

    test('shares one refresh between concurrent requests', () async {
      final fixture = DioFixture();

      final responses = await Future.wait([
        fixture.dio.get<Object?>('/a'),
        fixture.dio.get<Object?>('/b'),
        fixture.dio.get<Object?>('/c'),
      ]);

      expect(responses.map((r) => r.statusCode), [200, 200, 200]);
      expect(fixture.refresher.calls, 1);
      expect(fixture.adapter.requests, hasLength(6));
    });

    test('passes the 401 on when the manager cannot refresh', () async {
      final fixture = DioFixture(withRefresher: false);

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(call, throwsA(errors.withStatus(401)));
      expect(fixture.adapter.requests, hasLength(1));
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/token_manager_dio && dart test test/refresh_interceptor_test.dart`
Expected: the file compiles against the 0.1 interceptor and FAILS: the 0.1 interceptor reads the synchronous `tokens` getter, which is `null` until `initialize()` runs, so no header is sent (first test), a logged-out request goes out unauthenticated (second test), and nothing is replayed (the replay tests).

- [ ] **Step 4: Replace the interceptor and the barrel**

Overwrite `packages/token_manager_dio/lib/src/refresh_interceptor.dart` (this removes the `ignore_for_file` header, the deprecated API, `dynamic`, the magic string and the `baseUrl` mutation):

```dart
import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';

import 'refresh_interceptor_delegate.dart';
import 'request_marks.dart';

/// Dio interceptor that attaches tokens and replays a request once after an
/// auth failure.
class RefreshInterceptor<T> extends Interceptor {
  /// Creates an interceptor over [manager].
  ///
  /// A request that [delegate] reports as an auth failure is sent again once
  /// through [dio] with the tokens [manager] returns. Pass the [Dio] the
  /// interceptor is added to, so the replay keeps its adapter, its other
  /// interceptors and its timeouts; the replay is marked and never loops.
  /// Without [dio] a plain `Dio` sends the replay.
  RefreshInterceptor({
    required TokenManager<T> manager,
    required RefreshInterceptorDelegate<T> delegate,
    Dio? dio,
  }) : _manager = manager,
       _delegate = delegate,
       _dio = dio ?? Dio();

  final TokenManager<T> _manager;
  final RefreshInterceptorDelegate<T> _delegate;
  final Dio _dio;
  final RequestMarks<T> _marks = RequestMarks<T>();

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_marks.isReplay(options)) {
      handler.next(options);
      return;
    }
    try {
      final tokens = await _manager.validToken();
      _delegate.applyTokensToRequest(options, tokens);
      _marks.recordTokens(options, tokens);
      handler.next(options);
    } on Exception catch (error, stackTrace) {
      handler.reject(_failure(options, error, stackTrace), true);
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_delegate.shouldRefresh(err.response)) {
      handler.next(err);
      return;
    }
    try {
      final replayed = await _replay(err.requestOptions, err.response);
      if (replayed == null) {
        handler.next(err);
      } else {
        handler.resolve(replayed);
      }
    } on DioException catch (error) {
      handler.next(error);
    }
  }

  /// Sends [options] again with new tokens; `null` means the failure passes on.
  ///
  /// Throws a [DioException] when the tokens cannot be renewed or the replay
  /// fails.
  Future<Response<Object?>?> _replay(
    RequestOptions options,
    Response<Object?>? rejected,
  ) async {
    final used = _marks.tokensOf(options);
    if (used == null ||
        _marks.isReplay(options) ||
        !_marks.canReplay(options)) {
      return null;
    }
    try {
      final renewed = await _manager.validToken(rejected: used);
      if (identical(renewed, used)) {
        return null;
      }
      return await _send(_marks.replayOf(options, renewed), renewed);
    } on DioException {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _failure(options, error, stackTrace, response: rejected);
    }
  }

  Future<Response<Object?>> _send(RequestOptions options, T tokens) async {
    _delegate.applyTokensToRequest(options, tokens);
    // No type argument on purpose: `fetch<Object?>` would reset the response
    // type of the request to JSON, `fetch` infers `dynamic` and leaves it.
    final response = await _dio.fetch(options);
    return response;
  }

  DioException _failure(
    RequestOptions options,
    Object error,
    StackTrace stackTrace, {
    Response<Object?>? response,
  }) {
    return DioException(
      requestOptions: options,
      response: response,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
```

Overwrite `packages/token_manager_dio/lib/token_manager_dio.dart`:

```dart
export 'src/refresh_interceptor.dart' show RefreshInterceptor;
export 'src/refresh_interceptor_delegate.dart' show RefreshInterceptorDelegate;
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/token_manager_dio && dart test`
Expected: PASS (the ratchet, `request_marks_test.dart`, and 7 tests in `refresh_interceptor_test.dart`).

- [ ] **Step 6: Mutation check for the loop guard (do not commit)**

Temporarily replace `if (_marks.isReplay(options)) {` in `onRequest` with `if (false && _marks.isReplay(options)) {` and `_marks.isReplay(options) ||` in `_replay` with `false ||`, then run `dart test test/refresh_interceptor_test.dart`. Expected: `replays exactly once when the server keeps answering 401` FAILS. Restore both lines (`git diff` must show no change to those two lines) and rerun the file to see it pass.

- [ ] **Step 7: Gate and commit**

```bash
dart format packages && dart analyze packages
git add packages/token_manager_dio
git commit -m "feat(token_manager_dio): rewrite RefreshInterceptor on the new core

Attach the header through validToken, fail with NotAuthenticated when
logged out, and replay a rejected request exactly once, marked so that it
never loops even when the interceptor's own Dio sends it.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Expected from `dart analyze packages`: `No issues found!` (the old `example/main.dart` still compiles; it is rewritten in Task 6 and keeps its `ignore_for_file` until then).

---

### Task 4: Auth failures that arrive as responses (`validateStatus`) and the delegate docs

**Files:**
- Modify: `packages/token_manager_dio/lib/src/refresh_interceptor.dart` (insert `onResponse` between `onRequest` and `onError`)
- Modify: `packages/token_manager_dio/lib/src/refresh_interceptor_delegate.dart` (doc comments only)
- Create: `packages/token_manager_dio/test/refresh_interceptor_response_test.dart`
- Create: `packages/token_manager_dio/test/refresh_interceptor_delegate_test.dart`

**Interfaces:**
- Consumes: `DioFixture`, `DioErrors`, `BearerDelegate` (Task 3); `RefreshInterceptor` private `_replay`, `_marks`, `_delegate` (Task 3).
- Produces: `RefreshInterceptor.onResponse`, completing the public behaviour.

- [ ] **Step 1: Write the failing tests**

Create `packages/token_manager_dio/test/refresh_interceptor_response_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

import 'helpers/dio_errors.dart';
import 'helpers/dio_fixture.dart';

final class _NeverRefreshDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const _NeverRefreshDelegate();

  @override
  void applyTokensToRequest(RequestOptions options, TokenSet? tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens?.accessToken}';
  }

  @override
  bool shouldRefresh(Response<Object?>? response) => false;
}

void main() {
  const errors = DioErrors();

  group('which failures are replayed', () {
    test('replays a 401 that validateStatus accepted', () async {
      final fixture = DioFixture();

      final response = await fixture.dio.get<Object?>(
        '/me',
        options: Options(validateStatus: (_) => true),
      );

      expect(response.statusCode, 200);
      expect(fixture.adapter.requests, hasLength(2));
      expect(fixture.refresher.calls, 1);
    });

    test('replays an accepted 401 once when the server keeps it up', () async {
      final fixture = DioFixture(accepted: 'Bearer never');

      final response = await fixture.dio.get<Object?>(
        '/me',
        options: Options(validateStatus: (_) => true),
      );

      expect(response.statusCode, 401);
      expect(fixture.adapter.requests, hasLength(2));
    });

    test('follows the delegate when it refuses to refresh', () async {
      final fixture = DioFixture(delegate: const _NeverRefreshDelegate());

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(call, throwsA(errors.withStatus(401)));
      expect(fixture.adapter.requests, hasLength(1));
      expect(fixture.refresher.calls, 0);
    });
  });
}
```

Create `packages/token_manager_dio/test/refresh_interceptor_delegate_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'helpers/bearer_delegate.dart';

void main() {
  const delegate = BearerDelegate();

  Response<Object?> answer(int status) {
    return Response<Object?>(
      requestOptions: RequestOptions(path: '/me'),
      statusCode: status,
    );
  }

  test('asks for a refresh on a 401', () {
    expect(delegate.shouldRefresh(answer(401)), isTrue);
  });

  test('does not ask for a refresh on other statuses', () {
    expect(delegate.shouldRefresh(answer(200)), isFalse);
    expect(delegate.shouldRefresh(answer(403)), isFalse);
  });

  test('does not ask for a refresh without a response', () {
    expect(delegate.shouldRefresh(null), isFalse);
  });
}
```

- [ ] **Step 2: Run the tests to verify the right ones fail**

Run: `cd packages/token_manager_dio && dart test test/refresh_interceptor_response_test.dart test/refresh_interceptor_delegate_test.dart`
Expected: `replays a 401 that validateStatus accepted` FAILS (status 401, one request: `onResponse` has no replay yet) and `replays an accepted 401 once...` FAILS (one request instead of two). The refusing-delegate test and the three delegate tests PASS: they pin behaviour that already holds.

- [ ] **Step 3: Add `onResponse`**

In `packages/token_manager_dio/lib/src/refresh_interceptor.dart` insert, directly after `onRequest` and before `onError`:

```dart
  @override
  Future<void> onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) async {
    if (!_delegate.shouldRefresh(response)) {
      handler.next(response);
      return;
    }
    try {
      final replayed = await _replay(response.requestOptions, response);
      if (replayed == null) {
        handler.next(response);
      } else {
        handler.resolve(replayed);
      }
    } on DioException catch (error) {
      handler.reject(error, true);
    }
  }
```

- [ ] **Step 4: Update the delegate docs**

Overwrite `packages/token_manager_dio/lib/src/refresh_interceptor_delegate.dart` (signatures unchanged, so 0.1 subclasses still compile):

```dart
import 'package:dio/dio.dart';

/// Defines token application and refresh decision logic for Dio.
abstract class RefreshInterceptorDelegate<T> {
  /// Creates a delegate.
  const RefreshInterceptorDelegate();

  /// Applies authentication data from [tokens] to outgoing [options].
  ///
  /// Since 0.2 [tokens] is never `null`: a request without tokens fails with
  /// `NotAuthenticated` before it is sent. The parameter stays nullable so
  /// that 0.1 delegates keep compiling.
  void applyTokensToRequest(RequestOptions options, T? tokens);

  /// Returns `true` when [response] is an auth failure the request is
  /// replayed for.
  ///
  /// The default treats status 401 as an auth failure. [response] is `null`
  /// when the request failed without an answer, which is never one.
  bool shouldRefresh(Response? response) {
    if (response?.statusCode == 401) {
      return true;
    }

    return false;
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/token_manager_dio && dart test`
Expected: PASS (all earlier tests plus 3 in `refresh_interceptor_response_test.dart` and 3 in `refresh_interceptor_delegate_test.dart`).

- [ ] **Step 6: Gate and commit**

```bash
dart format packages && dart analyze packages
git add packages/token_manager_dio
git commit -m "feat(token_manager_dio): replay a 401 that arrives as a response

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Pin the awkward inputs: bodies, response type, failures, session changes

These tests describe behaviour Tasks 3 and 4 already implement, so they pass on first run. They exist to pin the Review Focus items, and two mutation checks prove that they can fail. If one fails on the first run, fix the interceptor, not the test.

**Files:**
- Create: `packages/token_manager_dio/test/refresh_interceptor_request_test.dart`
- Create: `packages/token_manager_dio/test/refresh_interceptor_failure_test.dart`

**Interfaces:**
- Consumes: `DioFixture` (including `adapter.gate`, `adapter.successBody`, `replayDio`, `DioFixture.initial`), `DioErrors`, `RequestMarks` behaviour (Tasks 2 and 3).
- Produces: nothing new.

- [ ] **Step 1: Write the request-shape tests**

Create `packages/token_manager_dio/test/refresh_interceptor_request_test.dart`:

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'helpers/dio_errors.dart';
import 'helpers/dio_fixture.dart';

void main() {
  const errors = DioErrors();

  test('keeps the query, the base url and the shared Dio options', () async {
    final fixture = DioFixture(ownDio: false);

    await fixture.dio.get<Object?>('/me', queryParameters: {'page': 2});

    final replay = fixture.adapter.requests.last;
    expect(replay.uri.toString(), 'https://api.test/me?page=2');
    expect(fixture.replayDio.options.baseUrl, isEmpty);
    expect(fixture.dio.options.baseUrl, 'https://api.test');
  });

  test('sends the same JSON body again', () async {
    final fixture = DioFixture();

    await fixture.dio.post<Object?>('/items', data: {'name': 'a'});

    expect(fixture.adapter.requests.map((r) => r.body), [
      '{"name":"a"}',
      '{"name":"a"}',
    ]);
  });

  test('sends a fresh clone of a FormData body', () async {
    final fixture = DioFixture();

    await fixture.dio.post<Object?>(
      '/upload',
      data: FormData.fromMap({'title': 'hello'}),
    );

    final bodies = fixture.adapter.requests.map((r) => r.body).toList();
    expect(bodies, hasLength(2));
    expect(bodies, everyElement(contains('hello')));
  });

  test('does not replay a stream body, and does not refresh', () async {
    final fixture = DioFixture();

    final call = fixture.dio.post<Object?>(
      '/upload',
      data: Stream.value(utf8.encode('payload')),
      options: Options(headers: {Headers.contentLengthHeader: 7}),
    );

    await expectLater(call, throwsA(errors.withStatus(401)));
    expect(fixture.adapter.requests, hasLength(1));
    expect(fixture.refresher.calls, 0);
  });

  test('keeps the plain response type of the request', () async {
    final fixture = DioFixture();
    fixture.adapter.successBody = 'not json';

    final response = await fixture.dio.get<String>('/text');

    expect(response.data, 'not json');
  });
}
```

- [ ] **Step 2: Write the failure and session-change tests**

Create `packages/token_manager_dio/test/refresh_interceptor_failure_test.dart`:

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/dio_errors.dart';
import 'helpers/dio_fixture.dart';

void main() {
  const errors = DioErrors();

  group('when the tokens cannot be renewed', () {
    test('surfaces InvalidGrant and signs the session out', () async {
      final fixture = DioFixture(refreshFailure: const InvalidGrant());

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(
        call,
        throwsA(errors.wrapping(isA<InvalidGrant>(), status: 401)),
      );
      expect(await fixture.manager.current(), isNull);
      expect(fixture.adapter.requests, hasLength(1));
    });

    test('surfaces a transient failure and keeps the session', () async {
      final fixture = DioFixture(refreshFailure: const Transient('offline'));

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(
        call,
        throwsA(errors.wrapping(isA<Transient>(), status: 401)),
      );
      expect(await fixture.manager.current(), DioFixture.initial);
    });
  });

  group('when the session changed while the request was in flight', () {
    Future<Future<Response<Object?>>> startHeldRequest(
      DioFixture fixture,
    ) async {
      fixture.adapter.gate = Completer<void>();
      final call = fixture.dio.get<Object?>('/me');
      await pumpEventQueue();
      expect(fixture.adapter.requests, hasLength(1));
      return call;
    }

    test('replays with the newer tokens without a second refresh', () async {
      final fixture = DioFixture();
      final call = await startHeldRequest(fixture);

      await fixture.manager.setTokens(
        const TokenSet(accessToken: 'new', refreshToken: 'refresh-2'),
      );
      fixture.adapter.gate?.complete();
      final response = await call;

      expect(response.statusCode, 200);
      expect(fixture.refresher.calls, 0);
      expect(fixture.adapter.requests.map((r) => r.authorization), [
        'Bearer old',
        'Bearer new',
      ]);
    });

    test('surfaces NotAuthenticated after a logout', () async {
      final fixture = DioFixture();
      final call = await startHeldRequest(fixture);
      final outcome = expectLater(
        call,
        throwsA(errors.wrapping(isA<NotAuthenticated>(), status: 401)),
      );

      await fixture.manager.logout();
      fixture.adapter.gate?.complete();

      await outcome;
      expect(fixture.adapter.requests, hasLength(1));
    });
  });
}
```

- [ ] **Step 3: Run the tests**

Run: `cd packages/token_manager_dio && dart test`
Expected: PASS (5 + 4 new tests).

- [ ] **Step 4: Mutation checks (do not commit)**

Run each, then restore the file (`git checkout -- packages/token_manager_dio/lib`) before the next:

1. In `refresh_interceptor.dart` change `await _dio.fetch(options);` to `await _dio.fetch<Object?>(options);`. Expected: `keeps the plain response type of the request` FAILS (the replay decodes `not json` as JSON).
2. In `request_marks.dart` change `FormData(:final clone) => clone(),` to `FormData() => options.data,`. Expected: `sends a fresh clone of a FormData body` FAILS.
3. In `request_marks.dart` change `options.data is! Stream<Object?>;` to `true;`. Expected: `does not replay a stream body, and does not refresh` FAILS.

After restoring, `git status --short` shows only the two new test files, and `dart test` passes again.

- [ ] **Step 5: Gate and commit**

```bash
dart format packages && dart analyze packages
git add packages/token_manager_dio/test
git commit -m "test(token_manager_dio): pin bodies, response type, failures and session changes

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Example, README, CHANGELOG and version 0.2.0

**Files:**
- Modify (replace): `packages/token_manager_dio/example/main.dart`
- Modify (replace): `packages/token_manager_dio/README.md`
- Modify: `packages/token_manager_dio/CHANGELOG.md` (prepend an entry)
- Modify: `packages/token_manager_dio/pubspec.yaml` (`version: 0.2.0`)

**Interfaces:**
- Consumes: the final public API from Tasks 3 and 4; core `TokenManager.create`, `InMemoryTokenStore`, `TokenSet`, `TokenSetInfo`, `TokenRefresher`.
- Produces: the releasable package; nothing for later tasks.

- [ ] **Step 1: Rewrite the example**

Overwrite `packages/token_manager_dio/example/main.dart` (no deprecated API, no `ignore_for_file`):

```dart
import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

final class _BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const _BearerDelegate();

  @override
  void applyTokensToRequest(RequestOptions options, TokenSet? tokens) {
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
  }
}

final class _ExampleRefresher implements TokenRefresher<TokenSet> {
  const _ExampleRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    // Call your token endpoint here. Throw InvalidGrant when the refresh
    // token was rejected for good, and Transient when a retry may succeed.
    return const TokenSet(
      accessToken: 'new_access_token',
      refreshToken: 'new_refresh_token',
    );
  }
}

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: const _ExampleRefresher(),
    info: const TokenSetInfo(),
  );
  await manager.setTokens(
    const TokenSet(accessToken: 'access_123', refreshToken: 'refresh_123'),
  );

  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
  // Pass the same Dio, so the replay keeps its adapter and interceptors.
  dio.interceptors.add(
    RefreshInterceptor<TokenSet>(
      manager: manager,
      delegate: const _BearerDelegate(),
      dio: dio,
    ),
  );

  await manager.dispose();
}
```

- [ ] **Step 2: Rewrite the README**

Overwrite `packages/token_manager_dio/README.md`:

````markdown
## token_manager_dio

[![Pub Version](https://img.shields.io/pub/v/token_manager_dio.svg)](https://pub.dev/packages/token_manager_dio)

`token_manager_dio` provides a Dio interceptor on top of `token_manager`:

- attaches a valid access token to every request (the manager refreshes it
  first when it is about to expire);
- when the server rejects a request, asks the manager for a replacement and
  sends the request again once;
- shares one refresh between concurrent requests;
- never loops: a replayed request is marked and is not replayed again.

## Installation

```yaml
dependencies:
  token_manager: ^0.2.0
  token_manager_dio: ^0.2.0
```

## Usage

```dart
import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const BearerDelegate();

  @override
  void applyTokensToRequest(RequestOptions options, TokenSet? tokens) {
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
  }
}

void configureClient(Dio dio, TokenManager<TokenSet> manager) {
  dio.interceptors.add(
    RefreshInterceptor<TokenSet>(
      manager: manager,
      delegate: const BearerDelegate(),
      // The Dio the interceptor is added to: the replay keeps its adapter,
      // its other interceptors and its timeouts.
      dio: dio,
    ),
  );
}
```

For a complete runnable example, see `example/main.dart`.

## What a failure looks like

The interceptor never swallows a failure to obtain or renew tokens. The
`DioException` carries the cause in `error`:

| `e.error` | Meaning |
|---|---|
| `NotAuthenticated` | There are no tokens: the user is logged out. Nothing was sent. |
| `InvalidGrant` | The refresh token was rejected for good; the manager signed the session out. |
| `Transient` | The refresh failed for a reason that may go away; the session is kept. |

On a refresh failure `e.response` is the 401 that started it. A replay that
the server rejects again reaches you as the usual `DioException` of that
second response.

## Replay rules

- Only the failures `RefreshInterceptorDelegate.shouldRefresh` accepts (status
  401 by default) trigger a replay, for any HTTP method.
- A replay carries `extra['token_manager_dio.replayed'] == true`; the tokens a
  request was sent with are in `extra['token_manager_dio.tokens']`.
- A `FormData` body is cloned. A `Stream` body cannot be sent twice, so the
  original error is returned and no refresh is started. A multipart file built
  from a single-subscription stream cannot be cloned either; use
  `MultipartFile.fromFile`, `fromBytes` or `fromString`.
- If the manager returns the same tokens that were rejected (it cannot
  refresh), the original error is returned.
- Without the `dio` argument the replay goes through a plain `Dio()`; pass the
  `Dio` you added the interceptor to unless you want that.
````

- [ ] **Step 3: Prepend the CHANGELOG entry**

Insert at the top of `packages/token_manager_dio/CHANGELOG.md`, above `## 0.1.0 - 2026-03-27`, followed by a blank line:

```markdown
## 0.2.0 - Unreleased

### Changed
- `RefreshInterceptor<T>` is built on the new `token_manager` core: the header
  comes from `TokenManager.validToken()` and a rejected request is replayed
  after `validToken(rejected: ...)`. The constructor and
  `RefreshInterceptorDelegate<T>` (`applyTokensToRequest`, `shouldRefresh`) are
  source compatible with 0.1.
- Requires `token_manager` 0.2.0 and no longer uses its deprecated API
  (`tokens`, `waitForFresh`, `executeRefresh`, `initialize`).
- `applyTokensToRequest` now always receives non-null tokens.
- The replay is sent with `Dio.fetch` on a copy of the request: the `Dio` given
  as `dio` keeps its `baseUrl` (0.1 overwrote it), the response type of the
  request is kept, and a `FormData` body is cloned.
- The request is no longer tagged with `extra['_auth_tokens']`; the interceptor
  uses `extra['token_manager_dio.tokens']`.

### Behaviour changes
- A request made while logged out fails with a `DioException` whose `error` is
  `NotAuthenticated` and is not sent. 0.1 sent it without credentials.
- A failure to renew tokens is no longer swallowed: the `DioException.error` is
  `InvalidGrant` (the session ended) or `Transient` (the session is kept), with
  the original 401 as `response`. 0.1 swallowed refresh errors and replayed
  with stale or missing tokens.
- A replay is marked with `extra['token_manager_dio.replayed']` and is replayed
  at most once. This ends the endless loop of 0.1 when the `Dio` that owns the
  interceptor was passed as `dio` and the server kept answering 401.
- If the manager returns the tokens that were rejected, the original error is
  returned instead of sending the same request again.
- A request with a `Stream` body is not replayed and starts no refresh; the
  original error is returned.
- Refresh now follows the core: tokens close to expiry (`skew`, 30 seconds by
  default) are refreshed before the request, and there is no `waitForFresh`
  step because `validToken` joins a refresh in flight.
```

- [ ] **Step 4: Bump the version**

In `packages/token_manager_dio/pubspec.yaml` change `version: 0.1.0` to `version: 0.2.0`. Leave the `token_manager:` constraint as decided in Task 1 step 1.

- [ ] **Step 5: Full verification**

```bash
dart pub get
dart format packages
dart format --output=none --set-exit-if-changed packages
dart analyze packages
cd packages/token_manager_dio && dart test && dart pub publish --dry-run
```

Expected: `dart pub get` clean; the format check exits 0; `dart analyze packages` prints `No issues found!`; `dart test` passes (32 tests); `dart pub publish --dry-run` shows no warning about the CHANGELOG. It may warn that the workspace constraint on `token_manager` is not published yet; that is the release handoff below, not a defect of this task. Also run `grep -rn "ignore_for_file\|dynamic\|waitForFresh\|executeRefresh" packages/token_manager_dio/lib packages/token_manager_dio/example`; expected: no match except the word `dynamic` inside the one comment in `_send`.

- [ ] **Step 6: Commit**

```bash
git add packages/token_manager_dio
git commit -m "feat(token_manager_dio): release 0.2.0 with the new example and docs

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Release handoff (not part of this branch)

- **Coordinated version bump (needs one owner).** Publishing `token_manager_dio` 0.2.0 requires `token_manager: ^0.2.0`, which needs the core `pubspec.yaml` at `0.2.0` and `token_manager_grpc` at `^0.2.0` in the same commit, or `dart pub get` fails for the whole workspace (verified: with the core at `0.2.0`, `token_manager_grpc`'s `^0.1.0` fails resolution). Do this as one small `build:` commit on `main` before the adapter PRs merge (or in the release phase), then change this package's constraint to `^0.2.0` and rerun Task 6 step 5.
- **CI** (`.github/workflows/ci.yml` is untouched here): add a step next to "Test token_manager": `Test token_manager_dio`, `working-directory: packages/token_manager_dio`, `run: dart test`. The package's test run is offline and fast, and the size ratchet runs inside it. The format and analyze steps already cover `packages`. Later, for phase 5: a `publish-dry-run` job running `dart pub publish --dry-run` in this package and the `token_manager_dio-v*` tag in `publish.yml`.
- **Root `README.md`** still says `token_manager_dio: ^0.1.0` in its quick start; update it with the release commit (not touched here to avoid conflicts with the other adapter branches).
- **Possible follow-up:** the 474-line `size_limits.dart` helper is now copied into each package; if more packages gain one, extract it (a dev-only package) rather than copy again.

## Self-review

**Spec coverage** (section 6 "dio" bullet and phase 3 item 1):

| Requirement | Task |
|---|---|
| Plain `Interceptor`, not `QueuedInterceptor` | 3 |
| Header through `validToken()`, tokens remembered per request | 2, 3 |
| Replay once through the user's `Dio`, marker in `extra` prevents re-entry (also with the owning `Dio`) | 2, 3 (loop tests, mutation check) |
| `rejected` compare (late 401 does not refresh again) and "identical result passes the error on" | 3, 5 |
| `FormData` cloned; stream bodies not replayed, original error returned | 2, 5 |
| No `baseUrl` mutation | 3, 5 |
| Refresh failures and `NotAuthenticated` surface (not swallowed) | 3, 5 |
| `shouldRefresh` honoured, also for `validateStatus`-accepted 401 | 4 |
| No `dynamic`, no deprecated API, no `ignore_for_file` | 3, 6 |
| Concurrent 401s produce exactly one refresh and one replay each (phase 3 "done when") | 3 |
| Tests on a stub `HttpClientAdapter` | 3, 4, 5 |
| Public names and `RefreshInterceptorDelegate` source compatible | 3, 4 |
| CHANGELOG, README, example, 0.2.0 | 6 |

Not in this plan, by design: the spec's `DioTokenInterceptor` / `applyTo` rename (the ruling keeps the 0.1 names), a separate refresh client (the core refreshes through the user's `TokenRefresher`), and CI edits.

**Placeholders:** none.

**Type consistency:** `RequestMarks<T>` members (`tokensOf`, `recordTokens`, `isReplay`, `canReplay`, `replayOf`) are the same in Tasks 2, 3 and 5. `DioFixture` parameters (`signedIn`, `withRefresher`, `refreshFailure`, `ownDio`, `accepted`, `delegate`) and fields (`adapter`, `refresher`, `manager`, `dio`, `replayDio`, `initial`) match every test that uses them. `_replay(RequestOptions, Response<Object?>?)` is called identically from `onError` (Task 3) and `onResponse` (Task 4).
