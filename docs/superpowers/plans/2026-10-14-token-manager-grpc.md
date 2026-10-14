# token_manager_grpc 0.2 rewrite: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `packages/token_manager_grpc` onto the 0.2 core (`TokenManager.authorize` for unary calls, `TokenManager.authorizeStream` for streaming calls) so that replays are single-flight and bounded, streams never duplicate responses, and the returned `ResponseFuture`/`ResponseStream` keep the headers, trailers and cancel of the call that actually answered.

**Architecture:** The adapter wraps every `send`/`open` closure it hands to the core in a small per-call tracker, `CallAttempts`, which records each gRPC call the core makes (the first one and, after a rejection, the replay). The `ResponseFuture`/`ResponseStream` views returned to the user read headers, trailers and cancel from that tracker once the call is settled (no further replay is possible). The core gets **no new API**: only a version bump, a documented per-attempt contract and two pinning tests.

**Tech Stack:** Dart 3.10+ pub workspace, `package:grpc` (`>=3.2.0 <6.0.0`, verified against 5.1.0), `package:async` (`DelegatingFuture`), `package:test`.

**Spec:** `docs/superpowers/specs/2026-10-14-token-manager-redesign-design.md`: section 5 (core API, `authorize`, `authorizeStream`, and the final-review note that `authorizeStream` returns a plain `Stream<R>` without the replayed call's headers and trailers), section 6 (adapters and streams, gRPC bullet), section 7 (migration), roadmap phase 3 item 3. The design rules in `CLAUDE.md` apply on top.

## Global Constraints

- Branch `feat/token-manager-grpc-0.2`, created from `main` at `3549079`; never commit to `main`. Run git from the repository root.
- Every commit uses Conventional Commits with a package scope (`feat(token_manager_grpc): ...`, `refactor(...)`, `test(...)`, `docs(...)`, `build: ...`) and ends with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. A refactor is its own commit.
- The core (`packages/token_manager`) stays pure Dart with no runtime dependencies and knows nothing about gRPC. This plan adds no public API to it.
- Public API of `token_manager_grpc` stays source-compatible: `RefreshInterceptor<T>` keeps its `const` constructor with named `manager` and `delegate`; `RefreshInterceptorDelegate<T>` keeps `buildCallOptions(T? tokens) -> grpc.CallOptions?` and `shouldRefresh(grpc.GrpcError? error) -> bool`.
- Unary calls go through `TokenManager.authorize`; streaming calls through `TokenManager.authorizeStream`. The adapter never calls the refresher and never replays by itself.
- A streaming call is reopened only before its first response; a response is never delivered twice.
- No `await for`, no `catch` without `on`, `Error` is never caught, no `!`, no `dynamic`, no local named functions in `lib/`, `late` only with a comment saying why.
- Size limits: lib file 300 lines, test file 500, method 40, parameters 5, nesting 3, about 15 members per class, one public class per file, no `utils`/`helpers`/`common` in `lib/`, no `part`.
- `dart format --output=none --set-exit-if-changed packages` exits 0 and `dart analyze packages` prints `No issues found!` at the end of every task.
- Tests ship in the same commit as the code; no network; one behaviour per test, named after the behaviour.
- `token_manager_grpc` becomes `0.2.0` and depends on `token_manager: ^0.2.0`. Do not modify `.github/workflows/ci.yml` (see "CI needs" at the end).
- All code, comments and docs are in English.

## Review Focus

These inputs follow from the spec but no happy-path test would hit them; each has a pinning test in the task in brackets.

1. The first call is rejected with a trailers-only `UNAUTHENTICATED` (its headers resolve successfully, then the error arrives): the user's `headers`/`trailers` must be the replay's, never the rejected call's. [Task 5 "headers and trailers come from the replayed call", Task 6 "headers and trailers come from the reopened call"]
2. The user calls `cancel()` while the refresh is in flight: no second call is made and the caller sees `CANCELLED`. [Task 5 "cancel during the refresh prevents the replay", Task 6 "cancel during the refresh never opens a second call"]
3. A call's `headers`/`trailers` future fails and nobody awaits it: nothing escapes as an uncaught zone error, but an awaiting caller still sees the error. [Task 2, Task 5 "a failing header future does not escape to the zone"]
4. A client-streaming or bidirectional call (several requests, or a request stream still open) is rejected: the error is surfaced, the call is not reopened and the request stream is never listened to twice. [Task 3, Task 6 "a client stream with several requests is never reopened"]
5. The listener cancels before the token arrives or before the first response: no call is made (or it is cancelled), and `headers` still resolves instead of hanging. [Task 4 "settles when cancelled before any event", Task 6 "cancelling before the token arrives never makes a call"]

## Core API decision: adapter-only, no core extension

The user approved a small additive core extension if gRPC needs one. Three designs were compared:

| Design | What changes in the core | Verdict |
|---|---|---|
| **A. Adapter-only** | Nothing in the API. The adapter's `open`/`send` closure creates the gRPC call, so it already sees every attempt; it records the latest one in `CallAttempts`. | **Chosen.** Correct (argued below), zero new core surface. |
| B. `onAttempt(handle)` callback on `authorizeStream` | New optional named parameter `void Function(Object attempt)? onAttempt`, called when the relay opens an attempt. | Redundant: it reports exactly what the `open` closure already sees, and it does not report the one fact the adapter needs and cannot get from it, namely when an attempt becomes final. The adapter would keep all of its settle logic. |
| C. New result type (`AuthorizedStream<R, A>` with `attempt` and `settled`) | A second public type in the barrel and either a changed return type of `authorizeStream` (breaking) or a parallel method. | Largest surface; the attempt handle type would be generic over a transport type the core must not know; gql and http adapters gain nothing. |

**Chosen API, in one paragraph.** No new core API. `token_manager_grpc` calls the existing `TokenManager.authorize<R>(send, isAuthFailure:)` and `TokenManager.authorizeStream<R>(open, isAuthFailure:)` unchanged, and keeps the current call in its own `CallAttempts` object: its `send`/`open` closures make the gRPC call through `CallAttempts.unary`/`CallAttempts.streaming`, which records the call as the latest attempt. The call is *settled* (its headers and trailers become the ones the user sees) when the core can no longer replay: for unary calls when the `authorize` future completes, for streaming calls when the relayed stream delivers its first event, error or end, or is cancelled (`SettlingStream`). The core only documents and pins the contract the adapter relies on: `send`/`open` runs once per attempt, at most twice, never after the listener cancelled, and an exception it throws is treated as the attempt's failure (Task 1).

**Why adapter-only is correct.** (1) `RelayStream._attach` calls `open` synchronously before subscribing, and `AuthorizedCall.run` calls `send` once per attempt, so the latest recorded call is always the one whose events the user sees. (2) A replayed attempt's stale call is cancelled by the relay before the new one opens, so no event of a replaced call reaches the user. (3) The moments at which the attempt becomes final are exactly the moments the relay itself commits (first event, forwarded error, end, cancel); they are observable on the relayed stream, which the adapter owns, and on the `authorize` future. A core hook could not settle any earlier: after a trailers-only `UNAUTHENTICATED` the rejected call's headers have already resolved, so "first headers to arrive" is wrong in any design. (4) Cancel between attempts (during the refresh) is handled by `CallAttempts` refusing to make a new call: the closure throws a cancelled `GrpcError`, which the core turns into the call's error (pinned in Task 1).

**Trade-off accepted.** For a streaming call, `headers` resolves when the first response, error or end arrives rather than when the header frame arrives. grpc-dart servers send headers together with the first response unless a handler sends them explicitly, so in practice the delay is nil; it is recorded under "Behaviour changes" in the CHANGELOG.

## File structure

`packages/token_manager_grpc/`:

| Path | Status | Responsibility |
|---|---|---|
| `lib/token_manager_grpc.dart` | modify | barrel: `show RefreshInterceptor`, `show RefreshInterceptorDelegate` |
| `lib/src/refresh_interceptor.dart` | rename from `auth_client_interceptor.dart`, rewrite | `RefreshInterceptor<T>`: wires gRPC invokers to `authorize`/`authorizeStream` |
| `lib/src/refresh_interceptor_delegate.dart` | modify (docs only) | `RefreshInterceptorDelegate<T>` |
| `lib/src/call_attempts.dart` | create | `CallAttempts`: latest call, settle, headers, trailers, cancel |
| `lib/src/request_log.dart` | create | `RequestLog<Q>`: whether a streaming call may be made again, and its requests |
| `lib/src/settling_stream.dart` | create | `SettlingStream<R>`: lifecycle-faithful relay that settles on first event or cancel |
| `lib/src/attempt_response_future.dart` | create | `AttemptResponseFuture<R>`: `grpc.ResponseFuture` view |
| `lib/src/attempt_response_stream.dart` | create | `AttemptResponseStream<R>`: `grpc.ResponseStream` view |
| `lib/src/async_response_future.dart` | delete (Task 5) | unexported 0.1 wrapper |
| `lib/src/async_response_stream.dart` | delete (Task 6) | unexported 0.1 wrapper |
| `test/helpers/*.dart` | create | fakes for calls and invokers, fixture, delegate, refresher, size limits |
| `test/*_test.dart`, `test/quality/size_limits_test.dart` | create | tests |
| `pubspec.yaml`, `CHANGELOG.md`, `README.md`, `example/main.dart` | modify | 0.2.0 |

`packages/token_manager/`: `pubspec.yaml` (version), `lib/src/token_manager.dart` (doc comments only), `test/engine/relay_stream_test.dart`, `test/engine/authorized_call_test.dart` (pinning tests). `packages/token_manager_dio/pubspec.yaml`: the `token_manager` constraint only.

Test layout: `lib/src/x.dart` is tested in `test/x_test.dart` (the package has no subfolders under `lib/src/`), except `refresh_interceptor.dart`, whose unary and streaming behaviour get one test file each to stay under 500 lines.

---

### Task 1: Core 0.2.0 and the per-attempt contract

**Files:**
- Modify: `packages/token_manager/pubspec.yaml` (line 3), `packages/token_manager_dio/pubspec.yaml` (line 16), `packages/token_manager_grpc/pubspec.yaml` (line 16)
- Modify: `packages/token_manager/lib/src/token_manager.dart:77-95` (doc comments of `authorize` and `authorizeStream`)
- Test: `packages/token_manager/test/engine/relay_stream_test.dart`, `packages/token_manager/test/engine/authorized_call_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: the workspace resolves with `token_manager` at version `0.2.0` and both adapters constrained to `^0.2.0`. The documented contract later tasks rely on: `send`/`open` runs once per attempt, at most twice, never after the stream's listener cancelled; an exception thrown by `open` becomes the stream's error and ends it; an exception thrown by `send` (synchronously or through its future) fails that attempt.

- [ ] **Step 1: Move the workspace to token_manager 0.2.0**

`packages/token_manager_grpc` must depend on `token_manager: ^0.2.0` (it uses the 0.2 API), and a workspace only resolves when every member's constraint matches the in-repo core version, so the core version and both adapter constraints change together. The core's `CHANGELOG.md` already has a `0.2.0 - Unreleased` section; no entry is added.

```bash
cd /home/genius/projects/dart_token_manager
sed -i 's/^version: 0.1.0$/version: 0.2.0/' packages/token_manager/pubspec.yaml
sed -i 's/^  token_manager: \^0.1.0$/  token_manager: ^0.2.0/' packages/token_manager_dio/pubspec.yaml packages/token_manager_grpc/pubspec.yaml
grep -n "^version\|token_manager:" packages/token_manager/pubspec.yaml packages/token_manager_dio/pubspec.yaml packages/token_manager_grpc/pubspec.yaml
dart pub get
```

Expected: the grep shows `version: 0.2.0` for the core and `token_manager: ^0.2.0` for dio and grpc; `dart pub get` ends with `Got dependencies!`.

- [ ] **Step 2: Commit the version move**

```bash
git add packages/token_manager/pubspec.yaml packages/token_manager_dio/pubspec.yaml packages/token_manager_grpc/pubspec.yaml
git commit -m "build: move the workspace to token_manager 0.2.0

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Write the pinning tests**

Append these two tests at the end of `main()` in `packages/token_manager/test/engine/relay_stream_test.dart` (before the final `}`); they reuse the file's `_Unauthorized`, `_Source`, `sources` and `settle`:

```dart
  test(
    'an exception thrown by open becomes an error and ends the stream',
    () async {
      final errors = <Object>[];
      var done = false;
      final subscription = RelayStream<String, int>(
        acquire: () async => 'a',
        renew: (rejected) async => 'b',
        open: (tokens) => throw Exception('refused'),
        isAuthFailure: (error) => error is _Unauthorized,
      ).stream.listen((_) {}, onError: errors.add, onDone: () => done = true);
      await settle();

      expect(errors.single, isA<Exception>());
      expect(done, isTrue);
      await subscription.cancel();
    },
  );

  test('an exception thrown by open on the reopen becomes an error and ends '
      'the stream', () async {
    final errors = <Object>[];
    var done = false;
    final subscription = RelayStream<String, int>(
      acquire: () async => 'a',
      renew: (rejected) async => 'b',
      open: (tokens) {
        if (sources.isNotEmpty) {
          throw Exception('refused');
        }
        final source = _Source(tokens);
        sources.add(source);
        return source.controller.stream;
      },
      isAuthFailure: (error) => error is _Unauthorized,
    ).stream.listen((_) {}, onError: errors.add, onDone: () => done = true);
    await settle();

    sources.single.controller.addError(const _Unauthorized());
    await settle();

    expect(errors.single, isA<Exception>());
    expect(done, isTrue);
    expect(sources, hasLength(1));
    await subscription.cancel();
  });
```

In `packages/token_manager/test/engine/authorized_call_test.dart`, add this class right after `_Unauthorized`:

```dart
final class _Cancelled implements Exception {
  const _Cancelled();
}
```

and append this test at the end of `main()`:

```dart
  test('an exception that send throws on the replay fails the call', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(hours: 1));
    await engine.setTokens(old);
    var sends = 0;

    final result = AuthorizedCall(engine).run<String>(
      (used) {
        sends++;
        if (identical(used, old)) {
          return Future<String>.error(const _Unauthorized());
        }
        throw const _Cancelled();
      },
      isAuthFailure: isUnauthorized,
    );
    await settle();
    fixture.refresher.complete(
      fixture.tokens(const Duration(hours: 1), access: 'b'),
    );

    await expectLater(result, throwsA(isA<_Cancelled>()));
    expect(sends, 2);
  });
```

- [ ] **Step 4: Run the pinning tests**

Run: `cd packages/token_manager && dart test test/engine/relay_stream_test.dart test/engine/authorized_call_test.dart`
Expected: PASS (14 + 9 tests). These tests pin behaviour that already exists. If one fails, stop and report: the adapter design in this plan depends on it.

- [ ] **Step 5: Document the contract**

In `packages/token_manager/lib/src/token_manager.dart`, replace the doc comments of `authorize` and `authorizeStream` (keep the signatures and bodies):

```dart
  /// Runs [send] with valid tokens, replaying it once after an auth failure.
  ///
  /// [send] runs once per attempt, at most twice. An exception it throws,
  /// synchronously or through its future, fails that attempt like a failed
  /// call.
  Future<R> authorize<R>(
```

```dart
  /// Opens a stream with valid tokens, reopening it once after an early auth
  /// failure. Pause, resume and cancel reach the source stream.
  ///
  /// Nothing is opened until the stream is listened to. [open] runs once per
  /// attempt, at most twice, and never after the listener cancelled. An
  /// exception that [open] throws becomes the stream's error and ends it.
  Stream<R> authorizeStream<R>(
```

- [ ] **Step 6: Verify and commit**

Run from the repository root:

```bash
dart format packages && dart format --output=none --set-exit-if-changed packages
dart analyze packages
(cd packages/token_manager && dart test)
```

Expected: format changes 0 files on the second run, `No issues found!`, all core tests pass.

```bash
git add packages/token_manager/lib/src/token_manager.dart packages/token_manager/test/engine/relay_stream_test.dart packages/token_manager/test/engine/authorized_call_test.dart
git commit -m "docs(token_manager): document and pin the per-attempt contract of authorize and authorizeStream

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Name the interceptor file after its class, and track call attempts

**Files:**
- Rename: `packages/token_manager_grpc/lib/src/auth_client_interceptor.dart` -> `packages/token_manager_grpc/lib/src/refresh_interceptor.dart`
- Modify: `packages/token_manager_grpc/lib/token_manager_grpc.dart`, `packages/token_manager_grpc/pubspec.yaml`
- Create: `packages/token_manager_grpc/lib/src/call_attempts.dart`
- Create: `packages/token_manager_grpc/test/helpers/fake_unary_call.dart`
- Test: `packages/token_manager_grpc/test/call_attempts_test.dart`

**Interfaces:**
- Consumes: `grpc.ResponseFuture<R>`, `grpc.ResponseStream<R>`, `grpc.GrpcError.cancelled` from `package:grpc/grpc.dart`.
- Produces:
  - `final class CallAttempts` with `CallAttempts()`, `Future<Map<String, String>> get headers`, `Future<Map<String, String>> get trailers`, `grpc.ResponseFuture<R> unary<R>(grpc.ResponseFuture<R> Function() call)`, `grpc.ResponseStream<R> streaming<R>(grpc.ResponseStream<R> Function() call)`, `void settle()`, `void settleWhenDone(Future<Object?> response)`, `Future<void> cancel()`. After `cancel()`, `unary`/`streaming` throw `const grpc.GrpcError.cancelled('Cancelled by client.')` without calling `call`.
  - Test helper `final class FakeUnaryCall<R> extends DelegatingFuture<R> implements grpc.ResponseFuture<R>` with `FakeUnaryCall(grpc.CallOptions options, {Map<String, String> metadata = const {}, Exception? metadataFailure})`, fields `options`, `cancelled`, getter `String? authorization`, methods `succeed(R)`, `fail(Object)`. Its `cancel()` fails a pending call with `GrpcError.cancelled()`.
  - Barrel: `export 'src/refresh_interceptor.dart' show RefreshInterceptor;` and `export 'src/refresh_interceptor_delegate.dart' show RefreshInterceptorDelegate;`.

- [ ] **Step 1: Rename the interceptor file (refactor)**

```bash
cd /home/genius/projects/dart_token_manager
git mv packages/token_manager_grpc/lib/src/auth_client_interceptor.dart packages/token_manager_grpc/lib/src/refresh_interceptor.dart
```

Replace `packages/token_manager_grpc/lib/token_manager_grpc.dart` with:

```dart
export 'src/refresh_interceptor.dart' show RefreshInterceptor;
export 'src/refresh_interceptor_delegate.dart' show RefreshInterceptorDelegate;
```

Run: `dart analyze packages`
Expected: `No issues found!`

```bash
git add packages/token_manager_grpc/lib
git commit -m "refactor(token_manager_grpc): name the interceptor file after its class

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2: Add the test dependency**

Append to `packages/token_manager_grpc/pubspec.yaml`:

```yaml

dev_dependencies:
  test: ^1.31.0
```

Run: `dart pub get` (repository root). Expected: `Got dependencies!`

- [ ] **Step 3: Write the fake unary call**

Create `packages/token_manager_grpc/test/helpers/fake_unary_call.dart`:

```dart
import 'dart:async';

import 'package:async/async.dart';
import 'package:grpc/grpc.dart' as grpc;

/// A unary call whose outcome the test decides, like a call from a channel.
final class FakeUnaryCall<R> extends DelegatingFuture<R>
    implements grpc.ResponseFuture<R> {
  /// Creates a pending call made with [options] that reports [metadata] as
  /// its headers and trailers, or fails them with [metadataFailure].
  FakeUnaryCall(
    grpc.CallOptions options, {
    Map<String, String> metadata = const {},
    Exception? metadataFailure,
  }) : this._(Completer<R>(), options, metadata, metadataFailure);

  FakeUnaryCall._(
    this._result,
    this.options,
    this._metadata,
    this._metadataFailure,
  ) : super(_result.future);

  final Completer<R> _result;
  final Map<String, String> _metadata;
  final Exception? _metadataFailure;

  /// The options the call was made with.
  final grpc.CallOptions options;

  /// Whether [cancel] was called.
  bool cancelled = false;

  /// The `authorization` metadata the call was made with.
  String? get authorization => options.metadata['authorization'];

  /// Answers the call with [response].
  void succeed(R response) => _result.complete(response);

  /// Fails the call with [error].
  void fail(Object error) => _result.completeError(error);

  @override
  Future<Map<String, String>> get headers => _reportMetadata();

  @override
  Future<Map<String, String>> get trailers => _reportMetadata();

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_result.isCompleted) {
      _result.completeError(const grpc.GrpcError.cancelled());
    }
  }

  Future<Map<String, String>> _reportMetadata() async {
    final failure = _metadataFailure;
    if (failure != null) {
      throw failure;
    }
    return _metadata;
  }
}
```

- [ ] **Step 4: Write the failing tests**

Create `packages/token_manager_grpc/test/call_attempts_test.dart`:

```dart
import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';
import 'package:token_manager_grpc/src/call_attempts.dart';

import 'helpers/fake_unary_call.dart';

void main() {
  FakeUnaryCall<String> fakeCall(
    Map<String, String> metadata, {
    Exception? metadataFailure,
  }) => FakeUnaryCall<String>(
    grpc.CallOptions(),
    metadata: metadata,
    metadataFailure: metadataFailure,
  );

  test('headers and trailers are empty when no call was made', () async {
    final attempts = CallAttempts()..settle();

    expect(await attempts.headers, isEmpty);
    expect(await attempts.trailers, isEmpty);
  });

  test('headers stay pending until the attempts settle', () async {
    final attempts = CallAttempts();
    attempts.unary(() => fakeCall({'call': '1'}));
    var resolved = false;
    unawaited(attempts.headers.then((_) => resolved = true));
    await Future<void>.delayed(Duration.zero);

    expect(resolved, isFalse);
    attempts.settle();
    expect(await attempts.headers, {'call': '1'});
  });

  test('headers and trailers follow the latest call', () async {
    final attempts = CallAttempts();
    attempts
      ..unary(() => fakeCall({'call': '1'}))
      ..unary(() => fakeCall({'call': '2'}))
      ..settle();

    expect(await attempts.headers, {'call': '2'});
    expect(await attempts.trailers, {'call': '2'});
  });

  test('settleWhenDone settles after the response fails', () async {
    final attempts = CallAttempts();
    final call = attempts.unary(() => fakeCall({'call': '1'}));
    attempts.settleWhenDone(call);

    (call as FakeUnaryCall<String>).fail(Exception('boom'));

    expect(await attempts.headers, {'call': '1'});
  });

  test('cancel cancels the latest call', () async {
    final attempts = CallAttempts();
    final call = fakeCall({});
    attempts.unary(() => call);
    unawaited(call.then((_) {}, onError: (_) {}));

    await attempts.cancel();

    expect(call.cancelled, isTrue);
  });

  test('a call after cancel fails as cancelled without being made', () async {
    final attempts = CallAttempts();
    await attempts.cancel();
    var made = false;

    expect(
      () => attempts.unary(() {
        made = true;
        return fakeCall({});
      }),
      throwsA(
        isA<grpc.GrpcError>().having(
          (error) => error.code,
          'code',
          grpc.StatusCode.cancelled,
        ),
      ),
    );
    expect(made, isFalse);
  });

  test('a failing header future reaches the caller, not the zone', () async {
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      CallAttempts()
        ..unary(() => fakeCall({}, metadataFailure: Exception('lost')))
        ..settle();
      await Future<void>.delayed(Duration.zero);
    }, (error, stackTrace) => uncaught.add(error));

    expect(uncaught, isEmpty);
  });

  test('an awaited failing header future throws its error', () async {
    final attempts = CallAttempts()
      ..unary(() => fakeCall({}, metadataFailure: Exception('lost')))
      ..settle();

    await expectLater(attempts.headers, throwsA(isA<Exception>()));
  });
}
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `cd packages/token_manager_grpc && dart test test/call_attempts_test.dart`
Expected: FAIL to load: `lib/src/call_attempts.dart` does not exist (`CallAttempts` is undefined).

- [ ] **Step 6: Write `CallAttempts`**

Create `packages/token_manager_grpc/lib/src/call_attempts.dart`:

```dart
import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;

/// Tracks the gRPC calls made for one intercepted call and exposes the
/// headers, trailers and cancel of the call that answered.
///
/// A replay makes a new call. The headers and trailers follow the latest call
/// once [settle] runs, that is when no further replay can happen.
final class CallAttempts {
  /// Creates a tracker that has made no call yet.
  CallAttempts() {
    // An error stays visible to whoever awaits these futures, but one that
    // nobody awaits must not escape as an uncaught zone error.
    _headers.future.ignore();
    _trailers.future.ignore();
  }

  /// The metadata reported when no call was ever made.
  static const Map<String, String> _noMetadata = {};

  /// The message of the error that a call started after [cancel] fails with.
  static const String _cancelledMessage = 'Cancelled by client.';

  final Completer<Map<String, String>> _headers =
      Completer<Map<String, String>>();
  final Completer<Map<String, String>> _trailers =
      Completer<Map<String, String>>();
  _Call? _latest;
  bool _cancelled = false;
  bool _settled = false;

  /// The headers of the call that answered.
  Future<Map<String, String>> get headers => _headers.future;

  /// The trailers of the call that answered.
  Future<Map<String, String>> get trailers => _trailers.future;

  /// Makes a unary call with [call] and records it as the latest call.
  ///
  /// Throws a cancelled `GrpcError` without calling [call] after [cancel].
  grpc.ResponseFuture<R> unary<R>(grpc.ResponseFuture<R> Function() call) {
    _ensureNotCancelled();
    final made = call();
    _latest = (
      headers: () => made.headers,
      trailers: () => made.trailers,
      cancel: made.cancel,
    );
    return made;
  }

  /// Makes a streaming call with [call] and records it as the latest call.
  ///
  /// Throws a cancelled `GrpcError` without calling [call] after [cancel].
  grpc.ResponseStream<R> streaming<R>(grpc.ResponseStream<R> Function() call) {
    _ensureNotCancelled();
    final made = call();
    _latest = (
      headers: () => made.headers,
      trailers: () => made.trailers,
      cancel: made.cancel,
    );
    return made;
  }

  /// Fixes the latest call as the one whose headers and trailers are
  /// reported; later calls do nothing.
  void settle() {
    if (_settled) {
      return;
    }
    _settled = true;
    final latest = _latest;
    if (latest == null) {
      _headers.complete(_noMetadata);
      _trailers.complete(_noMetadata);
      return;
    }
    _follow(latest.headers(), _headers);
    _follow(latest.trailers(), _trailers);
  }

  /// Settles once [response] completes, with a value or an error.
  void settleWhenDone(Future<Object?> response) {
    unawaited(response.then<void>(_settleOnValue, onError: _settleOnError));
  }

  /// Cancels the latest call and makes every later call fail as cancelled.
  Future<void> cancel() async {
    _cancelled = true;
    settle();
    await _latest?.cancel();
  }

  void _ensureNotCancelled() {
    if (_cancelled) {
      throw const grpc.GrpcError.cancelled(_cancelledMessage);
    }
  }

  void _settleOnValue(Object? _) => settle();

  void _settleOnError(Object _) => settle();

  void _follow(
    Future<Map<String, String>> source,
    Completer<Map<String, String>> target,
  ) {
    unawaited(
      source.then<void>(target.complete, onError: target.completeError),
    );
  }
}

/// What [CallAttempts] keeps of one call.
///
/// The metadata is read only once the call is known to be the one that
/// answered, so a replaced call's metadata is never listened to.
typedef _Call = ({
  Future<Map<String, String>> Function() headers,
  Future<Map<String, String>> Function() trailers,
  Future<void> Function() cancel,
});
```

Notes for the implementer: `grpc.Response` (the common interface of `ResponseFuture` and `ResponseStream`) is not exported by `package:grpc`, hence the two typed entry points and the record. The metadata getters are wrapped in closures on purpose: reading a replaced call's `headers` eagerly would create futures nobody listens to (Review Focus 3). `settleWhenDone` attaches an `onError` handler to the response future only to settle; the user's own `await` on the view still receives the error.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd packages/token_manager_grpc && dart test test/call_attempts_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 8: Gate and commit**

```bash
cd /home/genius/projects/dart_token_manager
dart format packages && dart format --output=none --set-exit-if-changed packages
dart analyze packages
git add packages/token_manager_grpc/pubspec.yaml packages/token_manager_grpc/lib/src/call_attempts.dart packages/token_manager_grpc/test
git commit -m "feat(token_manager_grpc): track the calls made for one intercepted call

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Decide whether a streaming call can be made again

**Files:**
- Create: `packages/token_manager_grpc/lib/src/request_log.dart`
- Test: `packages/token_manager_grpc/test/request_log_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `final class RequestLog<Q>` with `RequestLog(Stream<Q> requests)`, `bool get isReplayable` (true only when the request stream ended after at most one request), `Stream<Q> next()` (first call: the original stream, watched through a lifecycle-faithful `transform`; later calls: `Stream.fromIterable` of the recorded request). The original stream is never listened to twice.

Rationale: the spec says client-streaming request streams are single-subscription and never replayed. A server-streaming call made by generated code passes `Stream.fromIterable([request])`, one request that ends at once, so it is replayable from memory. Anything else (several requests, or a request stream still open when the rejection arrives) is not, and the adapter then reports the error instead of an auth failure.

- [ ] **Step 1: Write the failing tests**

Create `packages/token_manager_grpc/test/request_log_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager_grpc/src/request_log.dart';

void main() {
  test('the first call reads the original requests', () async {
    final log = RequestLog<int>(Stream<int>.fromIterable([1]));

    expect(await log.next().toList(), [1]);
  });

  test('a single ended request is replayable and sent again', () async {
    final log = RequestLog<int>(Stream<int>.fromIterable([1]));
    await log.next().toList();

    expect(log.isReplayable, isTrue);
    expect(await log.next().toList(), [1]);
  });

  test('requests that have not ended are not replayable', () async {
    final requests = StreamController<int>();
    final log = RequestLog<int>(requests.stream);
    final subscription = log.next().listen((_) {});
    requests.add(1);
    await Future<void>.delayed(Duration.zero);

    expect(log.isReplayable, isFalse);
    await subscription.cancel();
    await requests.close();
  });

  test('two requests are not replayable', () async {
    final log = RequestLog<int>(Stream<int>.fromIterable([1, 2]));
    await log.next().toList();

    expect(log.isReplayable, isFalse);
  });

  test('requests never read are not replayable', () {
    final log = RequestLog<int>(Stream<int>.fromIterable([1]));

    expect(log.isReplayable, isFalse);
  });

  test('pause, resume and cancel reach the original requests', () async {
    final requests = StreamController<int>();
    var cancelled = false;
    requests.onCancel = () => cancelled = true;
    final subscription = RequestLog<int>(
      requests.stream,
    ).next().listen((_) {});

    subscription.pause();
    expect(requests.isPaused, isTrue);
    subscription.resume();
    expect(requests.isPaused, isFalse);
    await subscription.cancel();
    expect(cancelled, isTrue);
    await requests.close();
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/token_manager_grpc && dart test test/request_log_test.dart`
Expected: FAIL to load: `lib/src/request_log.dart` does not exist.

- [ ] **Step 3: Write `RequestLog`**

Create `packages/token_manager_grpc/lib/src/request_log.dart`:

```dart
import 'dart:async';

/// Watches the request stream of a streaming call and tells whether the call
/// can be made again without listening to that stream a second time.
///
/// Only a stream that ended after at most one request, the shape of a
/// server-streaming call, can be made again: its request is sent again from
/// memory. Client-streaming and bidirectional calls are never made again.
final class RequestLog<Q> {
  /// Creates a log of [requests].
  RequestLog(this._requests);

  /// The most requests a call that can be made again may have sent.
  static const int _replayableRequests = 1;

  final Stream<Q> _requests;
  final List<Q> _sent = [];
  int _count = 0;
  bool _ended = false;
  bool _opened = false;

  /// Whether the requests ended after at most one request.
  bool get isReplayable => _ended && _count <= _replayableRequests;

  /// The request stream for the next call: the original one, watched, the
  /// first time, and the recorded request after that.
  Stream<Q> next() {
    if (_opened) {
      return Stream<Q>.fromIterable(List<Q>.of(_sent));
    }
    _opened = true;
    return _requests.transform(
      StreamTransformer<Q, Q>.fromHandlers(
        handleData: _record,
        handleDone: _end,
      ),
    );
  }

  void _record(Q request, EventSink<Q> sink) {
    _count++;
    if (_count <= _replayableRequests) {
      _sent.add(request);
    }
    sink.add(request);
  }

  void _end(EventSink<Q> sink) {
    _ended = true;
    sink.close();
  }
}
```

Only the first request is kept in memory, so a long bidirectional stream does not grow a buffer.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/token_manager_grpc && dart test test/request_log_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Gate and commit**

```bash
cd /home/genius/projects/dart_token_manager
dart format packages && dart format --output=none --set-exit-if-changed packages
dart analyze packages
git add packages/token_manager_grpc/lib/src/request_log.dart packages/token_manager_grpc/test/request_log_test.dart
git commit -m "feat(token_manager_grpc): tell whether a streaming call can be made again

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Settle the attempts on the first stream event

**Files:**
- Create: `packages/token_manager_grpc/lib/src/settling_stream.dart`
- Test: `packages/token_manager_grpc/test/settling_stream_test.dart`

**Interfaces:**
- Consumes: `CallAttempts` (`unary`, `settle`, `headers`) from Task 2; `FakeUnaryCall` from Task 2.
- Produces: `final class SettlingStream<R>` with `SettlingStream(Stream<R> source, CallAttempts attempts)` and `Stream<R> get stream` (single subscription). It calls `attempts.settle()` on the first data event, error, end, or on cancel; pause, resume and cancel reach `source`.

- [ ] **Step 1: Write the failing tests**

Create `packages/token_manager_grpc/test/settling_stream_test.dart`:

```dart
import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';
import 'package:token_manager_grpc/src/call_attempts.dart';
import 'package:token_manager_grpc/src/settling_stream.dart';

import 'helpers/fake_unary_call.dart';

void main() {
  late StreamController<int> source;
  late CallAttempts attempts;
  late bool settled;

  setUp(() {
    source = StreamController<int>();
    attempts = CallAttempts()
      ..unary(
        () => FakeUnaryCall<int>(grpc.CallOptions(), metadata: {'call': '1'}),
      );
    settled = false;
    unawaited(attempts.headers.then((_) => settled = true));
  });

  tearDown(() => source.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('relays events and settles on the first one', () async {
    final received = <int>[];
    final subscription = SettlingStream<int>(
      source.stream,
      attempts,
    ).stream.listen(received.add);
    await settle();
    expect(settled, isFalse);

    source.add(1);
    await settle();

    expect(received, [1]);
    expect(settled, isTrue);
    await subscription.cancel();
  });

  test('settles on the first error', () async {
    final subscription = SettlingStream<int>(
      source.stream,
      attempts,
    ).stream.listen((_) {}, onError: (_) {});

    source.addError(Exception('boom'));
    await settle();

    expect(settled, isTrue);
    await subscription.cancel();
  });

  test('settles and ends when the source ends', () async {
    var done = false;
    final subscription = SettlingStream<int>(
      source.stream,
      attempts,
    ).stream.listen((_) {}, onDone: () => done = true);

    await source.close();
    await settle();

    expect(settled, isTrue);
    expect(done, isTrue);
    await subscription.cancel();
  });

  test('settles when cancelled before any event', () async {
    final subscription = SettlingStream<int>(
      source.stream,
      attempts,
    ).stream.listen((_) {});
    await settle();

    await subscription.cancel();
    await settle();

    expect(settled, isTrue);
  });

  test('pause, resume and cancel reach the source', () async {
    var cancelled = false;
    source.onCancel = () => cancelled = true;
    final subscription = SettlingStream<int>(
      source.stream,
      attempts,
    ).stream.listen((_) {});

    subscription.pause();
    expect(source.isPaused, isTrue);
    subscription.resume();
    expect(source.isPaused, isFalse);
    await subscription.cancel();
    expect(cancelled, isTrue);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/token_manager_grpc && dart test test/settling_stream_test.dart`
Expected: FAIL to load: `lib/src/settling_stream.dart` does not exist.

- [ ] **Step 3: Write `SettlingStream`**

Create `packages/token_manager_grpc/lib/src/settling_stream.dart`:

```dart
import 'dart:async';

import 'call_attempts.dart';

/// Relays a stream and settles [CallAttempts] when the stream first delivers
/// something (an event, an error or its end) or is cancelled.
///
/// The source is subscribed with `listen`, so pause, resume and cancel reach
/// it.
final class SettlingStream<R> {
  /// Creates a relay of [source]; nothing happens until [stream] is listened
  /// to.
  SettlingStream(Stream<R> source, CallAttempts attempts)
    : _source = source,
      _attempts = attempts {
    _controller = StreamController<R>(
      onListen: _listen,
      onPause: _pause,
      onResume: _resume,
      onCancel: _cancel,
    );
  }

  final Stream<R> _source;
  final CallAttempts _attempts;

  // Assigned once in the constructor body: its callbacks need `this`.
  late final StreamController<R> _controller;

  StreamSubscription<R>? _subscription;

  /// The relayed stream; it supports a single subscription.
  Stream<R> get stream => _controller.stream;

  void _listen() {
    _subscription = _source.listen(_onData, onError: _onError, onDone: _onDone);
  }

  void _onData(R event) {
    _attempts.settle();
    _controller.add(event);
  }

  void _onError(Object error, StackTrace stackTrace) {
    _attempts.settle();
    _controller.addError(error, stackTrace);
  }

  void _onDone() {
    _attempts.settle();
    unawaited(_controller.close());
  }

  void _pause() => _subscription?.pause();

  void _resume() => _subscription?.resume();

  Future<void> _cancel() {
    _attempts.settle();
    final subscription = _subscription;
    _subscription = null;
    return subscription?.cancel() ?? Future<void>.value();
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/token_manager_grpc && dart test test/settling_stream_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Gate and commit**

```bash
cd /home/genius/projects/dart_token_manager
dart format packages && dart format --output=none --set-exit-if-changed packages
dart analyze packages
git add packages/token_manager_grpc/lib/src/settling_stream.dart packages/token_manager_grpc/test/settling_stream_test.dart
git commit -m "feat(token_manager_grpc): settle call attempts on the first stream event

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Unary calls through `TokenManager.authorize`

**Files:**
- Create: `packages/token_manager_grpc/lib/src/attempt_response_future.dart`
- Modify: `packages/token_manager_grpc/lib/src/refresh_interceptor.dart` (whole file), `packages/token_manager_grpc/lib/src/refresh_interceptor_delegate.dart` (doc comments)
- Delete: `packages/token_manager_grpc/lib/src/async_response_future.dart`
- Create: `packages/token_manager_grpc/test/helpers/fake_unary_invoker.dart`, `test/helpers/bearer_delegate.dart`, `test/helpers/counting_refresher.dart`, `test/helpers/grpc_fixture.dart`
- Test: `packages/token_manager_grpc/test/refresh_interceptor_unary_test.dart`

**Interfaces:**
- Consumes: `CallAttempts` (Task 2); `TokenManager<T>.authorize<R>(Future<R> Function(T tokens) send, {required bool Function(Object error) isAuthFailure})`, `TokenManager<String>.create(store:, refresher:)`, `InMemoryTokenStore<String>`, `TokenRefresher<String>`, `NotAuthenticated` from `package:token_manager/token_manager.dart`.
- Produces:
  - `final class AttemptResponseFuture<R> extends DelegatingFuture<R> implements grpc.ResponseFuture<R>` with `AttemptResponseFuture(Future<R> response, CallAttempts attempts)`; it calls `attempts.settleWhenDone(response)`; `headers`, `trailers`, `cancel()` delegate to `attempts`.
  - Private helpers on `RefreshInterceptor<T>`: `bool _isAuthFailure(Object error)` (`error is grpc.GrpcError && _delegate.shouldRefresh(error)`) and `grpc.CallOptions _withTokens(grpc.CallOptions options, T tokens)` (`options.mergedWith(_delegate.buildCallOptions(tokens))`); Task 6 reuses both.
  - Test helpers: `FakeUnaryInvoker<Q, R>` (`calls`, `metadataByCall`, `metadataFailure`, `invoke` tear-off matching `grpc.ClientUnaryInvoker<Q, R>`); `class BearerDelegate extends RefreshInterceptorDelegate<String>` (`const BearerDelegate()`, metadata `authorization: Bearer <token>`); `CountingRefresher implements TokenRefresher<String>` (n-th refresh returns `tn`; `calls`; optional `Completer<void>? gate`); `GrpcFixture` (`GrpcFixture({RefreshInterceptorDelegate<String> delegate = const BearerDelegate(), bool signedIn = true})`, fields `refresher`, `manager`, `interceptor`, static `method` (`ClientMethod<String, String>`), static `Future<void> settle()`). The session starts with token `t0`.

- [ ] **Step 1: Write the test helpers**

Create `packages/token_manager_grpc/test/helpers/fake_unary_invoker.dart`:

```dart
import 'package:grpc/grpc.dart' as grpc;

import 'fake_unary_call.dart';

/// A unary invoker that records every call it makes; each call stays
/// pending until the test answers it.
final class FakeUnaryInvoker<Q, R> {
  /// The calls made so far, in order.
  final List<FakeUnaryCall<R>> calls = [];

  /// The metadata that call number `n` reports, by `n`.
  final Map<int, Map<String, String>> metadataByCall = {};

  /// When set, every call fails its headers and trailers with it.
  Exception? metadataFailure;

  /// Makes a pending call; a tear-off matches `grpc.ClientUnaryInvoker`.
  grpc.ResponseFuture<R> invoke(
    grpc.ClientMethod<Q, R> method,
    Q request,
    grpc.CallOptions options,
  ) {
    final call = FakeUnaryCall<R>(
      options,
      metadata: metadataByCall[calls.length] ?? const {},
      metadataFailure: metadataFailure,
    );
    calls.add(call);
    return call;
  }
}
```

Create `packages/token_manager_grpc/test/helpers/bearer_delegate.dart`:

```dart
import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager_grpc/token_manager_grpc.dart';

/// Attaches the token as `authorization: Bearer <token>`.
class BearerDelegate extends RefreshInterceptorDelegate<String> {
  /// Creates the delegate.
  const BearerDelegate();

  @override
  grpc.CallOptions buildCallOptions(String? tokens) => grpc.CallOptions(
    metadata: {if (tokens != null) 'authorization': 'Bearer $tokens'},
  );
}
```

Create `packages/token_manager_grpc/test/helpers/counting_refresher.dart`:

```dart
import 'dart:async';

import 'package:token_manager/token_manager.dart';

/// A refresher whose n-th refresh returns the token `tn`.
final class CountingRefresher implements TokenRefresher<String> {
  /// How many refreshes started.
  int calls = 0;

  /// When set, every refresh waits for it before it returns.
  Completer<void>? gate;

  @override
  Future<String> refresh(String current) async {
    calls++;
    final token = 't$calls';
    await gate?.future;
    return token;
  }
}
```

Create `packages/token_manager_grpc/test/helpers/grpc_fixture.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

import 'bearer_delegate.dart';
import 'counting_refresher.dart';

/// A [TokenManager] holding the token `t0` and an interceptor over it.
final class GrpcFixture {
  /// Creates a fixture whose interceptor attaches tokens with [delegate];
  /// the session is signed out unless [signedIn].
  factory GrpcFixture({
    RefreshInterceptorDelegate<String> delegate = const BearerDelegate(),
    bool signedIn = true,
  }) {
    final refresher = CountingRefresher();
    final manager = TokenManager<String>.create(
      store: InMemoryTokenStore<String>(signedIn ? 't0' : null),
      refresher: refresher,
    );
    final interceptor = RefreshInterceptor<String>(
      manager: manager,
      delegate: delegate,
    );
    return GrpcFixture._(refresher, manager, interceptor);
  }

  GrpcFixture._(this.refresher, this.manager, this.interceptor);

  /// The method every test calls.
  static final grpc.ClientMethod<String, String> method =
      grpc.ClientMethod<String, String>(
        '/test.Echo/Call',
        utf8.encode,
        utf8.decode,
      );

  /// The refresher behind [manager]; its n-th refresh returns `tn`.
  final CountingRefresher refresher;

  /// The manager the interceptor takes tokens from.
  final TokenManager<String> manager;

  /// The interceptor under test.
  final RefreshInterceptor<String> interceptor;

  /// Lets every pending microtask and zero-delay timer run.
  static Future<void> settle() => Future<void>.delayed(Duration.zero);
}
```

- [ ] **Step 2: Write the failing tests**

Create `packages/token_manager_grpc/test/refresh_interceptor_unary_test.dart`:

```dart
import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/bearer_delegate.dart';
import 'helpers/fake_unary_invoker.dart';
import 'helpers/grpc_fixture.dart';

final class _PermissionDeniedDelegate extends BearerDelegate {
  const _PermissionDeniedDelegate();

  @override
  bool shouldRefresh(grpc.GrpcError? error) =>
      error?.code == grpc.StatusCode.permissionDenied;
}

void main() {
  const unauthenticated = grpc.GrpcError.unauthenticated();
  late GrpcFixture fixture;
  late FakeUnaryInvoker<String, String> invoker;

  setUp(() {
    fixture = GrpcFixture();
    invoker = FakeUnaryInvoker<String, String>();
  });

  grpc.ResponseFuture<String> call({grpc.CallOptions? options}) =>
      fixture.interceptor.interceptUnary<String, String>(
        GrpcFixture.method,
        'ping',
        options ?? grpc.CallOptions(),
        invoker.invoke,
      );

  test(
    'sends the call with the token metadata and the caller options',
    () async {
      final response = call(options: grpc.CallOptions(metadata: {'x': '1'}));
      await GrpcFixture.settle();
      invoker.calls.single.succeed('pong');

      expect(await response, 'pong');
      expect(invoker.calls.single.options.metadata, {
        'x': '1',
        'authorization': 'Bearer t0',
      });
    },
  );

  test('fails with NotAuthenticated without calling when signed out', () async {
    fixture = GrpcFixture(signedIn: false);

    await expectLater(call(), throwsA(isA<NotAuthenticated>()));
    expect(invoker.calls, isEmpty);
  });

  test('replays once with refreshed tokens after UNAUTHENTICATED', () async {
    final response = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].succeed('pong');

    expect(await response, 'pong');
    expect(invoker.calls.map((call) => call.authorization), [
      'Bearer t0',
      'Bearer t1',
    ]);
    expect(fixture.refresher.calls, 1);
  });

  test('a second UNAUTHENTICATED is surfaced after one replay', () async {
    final response = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].fail(unauthenticated);

    await expectLater(response, throwsA(unauthenticated));
    expect(invoker.calls, hasLength(2));
    expect(fixture.refresher.calls, 1);
  });

  test('another gRPC error is surfaced without a replay', () async {
    const unavailable = grpc.GrpcError.unavailable();
    final response = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(unavailable);

    await expectLater(response, throwsA(unavailable));
    expect(invoker.calls, hasLength(1));
    expect(fixture.refresher.calls, 0);
  });

  test('the delegate decides which errors are auth failures', () async {
    fixture = GrpcFixture(delegate: const _PermissionDeniedDelegate());
    final response = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(const grpc.GrpcError.permissionDenied());
    await GrpcFixture.settle();
    invoker.calls[1].succeed('pong');

    expect(await response, 'pong');
    expect(fixture.refresher.calls, 1);
  });

  test('headers and trailers come from the replayed call', () async {
    invoker.metadataByCall.addAll({
      0: {'call': '0'},
      1: {'call': '1'},
    });
    final response = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].succeed('pong');
    await response;

    expect(await response.headers, {'call': '1'});
    expect(await response.trailers, {'call': '1'});
  });

  test('headers are empty when no call was made', () async {
    fixture = GrpcFixture(signedIn: false);
    final response = call();
    await expectLater(response, throwsA(isA<NotAuthenticated>()));

    expect(await response.headers, isEmpty);
  });

  test('cancel reaches the call in flight', () async {
    final response = call();
    await GrpcFixture.settle();

    await response.cancel();

    expect(invoker.calls.single.cancelled, isTrue);
    await expectLater(response, throwsA(isA<grpc.GrpcError>()));
  });

  test('cancel during the refresh prevents the replay', () async {
    fixture.refresher.gate = Completer<void>();
    final response = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(unauthenticated);
    await GrpcFixture.settle();

    await response.cancel();
    fixture.refresher.gate?.complete();

    await expectLater(
      response,
      throwsA(
        isA<grpc.GrpcError>().having(
          (error) => error.code,
          'code',
          grpc.StatusCode.cancelled,
        ),
      ),
    );
    expect(invoker.calls, hasLength(1));
  });

  test('concurrent rejected calls share one refresh', () async {
    final first = call();
    final second = call();
    await GrpcFixture.settle();
    invoker.calls[0].fail(unauthenticated);
    invoker.calls[1].fail(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[2].succeed('a');
    invoker.calls[3].succeed('b');

    expect(await Future.wait([first, second]), ['a', 'b']);
    expect(fixture.refresher.calls, 1);
  });

  test('a failing header future does not escape to the zone', () async {
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      invoker.metadataFailure = Exception('lost');
      final response = call();
      await GrpcFixture.settle();
      invoker.calls.single.succeed('pong');
      await response;
      await GrpcFixture.settle();
    }, (error, stackTrace) => uncaught.add(error));

    expect(uncaught, isEmpty);
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/token_manager_grpc && dart test test/refresh_interceptor_unary_test.dart`
Expected: FAIL. The 0.1 unary path sends the call without tokens when signed out, never consults `shouldRefresh`, and forces `executeRefresh`, so at least "fails with NotAuthenticated without calling when signed out", "the delegate decides which errors are auth failures" and "cancel during the refresh prevents the replay" fail (other tests may fail or hang until the test timeout: the 0.1 adapter reads the synchronous `tokens` getter, which is `null` before a load).

- [ ] **Step 4: Write `AttemptResponseFuture`**

Create `packages/token_manager_grpc/lib/src/attempt_response_future.dart`:

```dart
import 'package:async/async.dart';
import 'package:grpc/grpc.dart' as grpc;

import 'call_attempts.dart';

/// A [grpc.ResponseFuture] whose headers, trailers and cancel follow the
/// call that answered, which may be a replay.
final class AttemptResponseFuture<R> extends DelegatingFuture<R>
    implements grpc.ResponseFuture<R> {
  /// Wraps [response] and settles [attempts] once it completes.
  AttemptResponseFuture(Future<R> response, CallAttempts attempts)
    : _attempts = attempts,
      super(response) {
    attempts.settleWhenDone(response);
  }

  final CallAttempts _attempts;

  @override
  Future<Map<String, String>> get headers => _attempts.headers;

  @override
  Future<Map<String, String>> get trailers => _attempts.trailers;

  @override
  Future<void> cancel() => _attempts.cancel();
}
```

(`DelegatingFuture` names its constructor parameter `_future`, so a super parameter cannot be used here; `use_super_parameters` does not fire on this form, so no `// ignore:` is needed.)

- [ ] **Step 5: Rewrite the unary path of the interceptor**

Replace the whole of `packages/token_manager_grpc/lib/src/refresh_interceptor.dart` with the following. `interceptStreaming` and `_buildAuthOptions` are the 0.1 code, kept verbatim until Task 6:

```dart
// interceptStreaming still uses the deprecated token_manager API until Task 6.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';

import 'async_response_stream.dart';
import 'attempt_response_future.dart';
import 'call_attempts.dart';
import 'refresh_interceptor_delegate.dart';

/// A gRPC client interceptor that sends calls with valid tokens and replays
/// a call once when the server rejects its tokens.
class RefreshInterceptor<T> implements grpc.ClientInterceptor {
  /// Creates an interceptor that takes tokens from [manager] and attaches
  /// them with [delegate].
  const RefreshInterceptor({
    required TokenManager<T> manager,
    required RefreshInterceptorDelegate<T> delegate,
  }) : _manager = manager,
       _delegate = delegate;

  final TokenManager<T> _manager;
  final RefreshInterceptorDelegate<T> _delegate;

  @override
  grpc.ResponseFuture<R> interceptUnary<Q, R>(
    grpc.ClientMethod<Q, R> method,
    Q request,
    grpc.CallOptions options,
    grpc.ClientUnaryInvoker<Q, R> invoker,
  ) {
    final attempts = CallAttempts();
    final response = _manager.authorize<R>(
      (tokens) => attempts.unary(
        () => invoker(method, request, _withTokens(options, tokens)),
      ),
      isAuthFailure: _isAuthFailure,
    );
    return AttemptResponseFuture<R>(response, attempts);
  }

  @override
  grpc.ResponseStream<R> interceptStreaming<Q, R>(
    grpc.ClientMethod<Q, R> method,
    Stream<Q> requests,
    grpc.CallOptions options,
    grpc.ClientStreamingInvoker<Q, R> invoker,
  ) => AsyncResponseStream.fromCallback((controller, setStream) async {
    await _manager.waitForFresh;
    final tokens = _manager.tokens;

    Future<void> forward(grpc.ResponseStream<R> stream) async {
      setStream(stream);
      await for (final item in stream) {
        controller.add(item);
      }
    }

    if (tokens == null) {
      await forward(invoker(method, requests, options));
      return;
    }

    try {
      await forward(
        invoker(
          method,
          requests,
          options.mergedWith(_buildAuthOptions(tokens)),
        ),
      );
    } catch (error) {
      if (error case grpc.GrpcError(code: grpc.StatusCode.unauthenticated)) {
        await _manager.executeRefresh();

        final refreshedTokens = _manager.tokens;

        if (refreshedTokens == null) {
          await forward(invoker(method, requests, options));
          return;
        }

        await forward(
          invoker(
            method,
            requests,
            options.mergedWith(_buildAuthOptions(refreshedTokens)),
          ),
        );
      } else {
        rethrow;
      }
    }
  });

  bool _isAuthFailure(Object error) =>
      error is grpc.GrpcError && _delegate.shouldRefresh(error);

  grpc.CallOptions _withTokens(grpc.CallOptions options, T tokens) =>
      options.mergedWith(_delegate.buildCallOptions(tokens));

  grpc.CallOptions? _buildAuthOptions(T tokens) =>
      _delegate.buildCallOptions(tokens);
}
```

Then delete the unused 0.1 unary wrapper:

```bash
git rm packages/token_manager_grpc/lib/src/async_response_future.dart
```

- [ ] **Step 6: Document that `shouldRefresh` is honoured**

In `packages/token_manager_grpc/lib/src/refresh_interceptor_delegate.dart`, change only the doc comments (bodies unchanged):

```dart
/// Attaches tokens to gRPC calls and recognises the errors that mean the
/// server rejected them.
abstract class RefreshInterceptorDelegate<T> {
```

```dart
  /// Builds the call options, usually metadata, that carry [tokens].
  ///
  /// The interceptor always passes tokens; the parameter stays nullable for
  /// compatibility with 0.1.
  grpc.CallOptions? buildCallOptions(T? tokens);

  /// Returns `true` when [error] means the server rejected the tokens.
  ///
  /// The interceptor then refreshes the tokens and replays the call once.
  /// The default accepts `UNAUTHENTICATED`.
  bool shouldRefresh(grpc.GrpcError? error) {
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd packages/token_manager_grpc && dart test`
Expected: PASS (all tests so far: 8 + 6 + 5 + 12).

- [ ] **Step 8: Gate and commit**

```bash
cd /home/genius/projects/dart_token_manager
dart format packages && dart format --output=none --set-exit-if-changed packages
dart analyze packages
git add packages/token_manager_grpc/lib packages/token_manager_grpc/test
git commit -m "feat(token_manager_grpc)!: send unary calls through TokenManager.authorize

A signed-out unary call now fails with NotAuthenticated instead of going out
without credentials, the delegate's shouldRefresh decides what an auth failure
is, and headers, trailers and cancel follow the replayed call.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Streaming calls through `TokenManager.authorizeStream`

**Files:**
- Create: `packages/token_manager_grpc/lib/src/attempt_response_stream.dart`
- Modify: `packages/token_manager_grpc/lib/src/refresh_interceptor.dart` (whole file)
- Delete: `packages/token_manager_grpc/lib/src/async_response_stream.dart`
- Create: `packages/token_manager_grpc/test/helpers/fake_stream_call.dart`, `packages/token_manager_grpc/test/helpers/fake_stream_invoker.dart`
- Test: `packages/token_manager_grpc/test/refresh_interceptor_streaming_test.dart`

**Interfaces:**
- Consumes: `CallAttempts.streaming` (Task 2), `RequestLog<Q>` (Task 3), `SettlingStream<R>` (Task 4), `AttemptResponseFuture<R>` (Task 5), `_isAuthFailure` and `_withTokens` (Task 5); `TokenManager<T>.authorizeStream<R>(Stream<R> Function(T tokens) open, {required bool Function(Object error) isAuthFailure})`; `GrpcFixture`, `CountingRefresher.gate` (Task 5).
- Produces: `final class AttemptResponseStream<R> extends StreamView<R> implements grpc.ResponseStream<R>` with `AttemptResponseStream(Stream<R> responses, CallAttempts attempts)`; `single` returns an `AttemptResponseFuture<R>`. Test helpers `FakeStreamCall<Q, R>` (`responses` controller, `options`, `sent`, `cancelled`, `authorization`) and `FakeStreamInvoker<Q, R>` (`calls`, `metadataByCall`, `invoke`, `closeAll()`). After this task `lib/` uses no deprecated API and has no `ignore_for_file`.

- [ ] **Step 1: Write the streaming fakes**

Create `packages/token_manager_grpc/test/helpers/fake_stream_call.dart`:

```dart
import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;

/// A streaming call whose responses the test pushes, like a call from a
/// channel: it listens to its request stream at once and records it.
final class FakeStreamCall<Q, R> extends StreamView<R>
    implements grpc.ResponseStream<R> {
  /// Creates a call made with [requests] and [options] that reports
  /// [metadata] as its headers and trailers.
  FakeStreamCall(
    Stream<Q> requests,
    grpc.CallOptions options, {
    Map<String, String> metadata = const {},
  }) : this._(StreamController<R>(), requests, options, metadata);

  FakeStreamCall._(
    this.responses,
    Stream<Q> requests,
    this.options,
    this._metadata,
  ) : super(responses.stream) {
    responses.onCancel = _onCancel;
    _requests = requests.listen(sent.add);
  }

  final Map<String, String> _metadata;
  StreamSubscription<Q>? _requests;

  /// The controller the test pushes responses into.
  final StreamController<R> responses;

  /// The options the call was made with.
  final grpc.CallOptions options;

  /// The requests the call has read so far.
  final List<Q> sent = [];

  /// Whether the call was cancelled, by [cancel] or by its listener.
  bool cancelled = false;

  /// The `authorization` metadata the call was made with.
  String? get authorization => options.metadata['authorization'];

  @override
  grpc.ResponseFuture<R> get single => throw UnsupportedError('not faked');

  @override
  Future<Map<String, String>> get headers async => _metadata;

  @override
  Future<Map<String, String>> get trailers async => _metadata;

  @override
  Future<void> cancel() async {
    await _onCancel();
    if (!responses.isClosed) {
      responses.addError(const grpc.GrpcError.cancelled());
      await responses.close();
    }
  }

  Future<void> _onCancel() async {
    cancelled = true;
    await _requests?.cancel();
  }
}
```

Create `packages/token_manager_grpc/test/helpers/fake_stream_invoker.dart`:

```dart
import 'package:grpc/grpc.dart' as grpc;

import 'fake_stream_call.dart';

/// A streaming invoker that records every call it makes.
final class FakeStreamInvoker<Q, R> {
  /// The calls made so far, in order.
  final List<FakeStreamCall<Q, R>> calls = [];

  /// The metadata that call number `n` reports, by `n`.
  final Map<int, Map<String, String>> metadataByCall = {};

  /// Makes a call; a tear-off matches `grpc.ClientStreamingInvoker`.
  grpc.ResponseStream<R> invoke(
    grpc.ClientMethod<Q, R> method,
    Stream<Q> requests,
    grpc.CallOptions options,
  ) {
    final call = FakeStreamCall<Q, R>(
      requests,
      options,
      metadata: metadataByCall[calls.length] ?? const {},
    );
    calls.add(call);
    return call;
  }

  /// Closes every call so that no test leaks a controller.
  Future<void> closeAll() async {
    for (final call in calls) {
      await call.responses.close();
    }
  }
}
```

- [ ] **Step 2: Write the failing tests**

Create `packages/token_manager_grpc/test/refresh_interceptor_streaming_test.dart`:

```dart
import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/fake_stream_invoker.dart';
import 'helpers/grpc_fixture.dart';

void main() {
  const unauthenticated = grpc.GrpcError.unauthenticated();
  late GrpcFixture fixture;
  late FakeStreamInvoker<String, String> invoker;
  late List<String> received;
  late List<Object> errors;

  setUp(() {
    fixture = GrpcFixture();
    invoker = FakeStreamInvoker<String, String>();
    received = [];
    errors = [];
  });

  tearDown(() => invoker.closeAll());

  grpc.ResponseStream<String> open([Stream<String>? requests]) =>
      fixture.interceptor.interceptStreaming<String, String>(
        GrpcFixture.method,
        requests ?? Stream<String>.fromIterable(['ping']),
        grpc.CallOptions(),
        invoker.invoke,
      );

  StreamSubscription<String> listen(grpc.ResponseStream<String> stream) =>
      stream.listen(received.add, onError: errors.add);

  test('opens the call with the token metadata and relays responses', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();
    invoker.calls.single.responses
      ..add('a')
      ..add('b');
    await GrpcFixture.settle();

    expect(invoker.calls.single.authorization, 'Bearer t0');
    expect(received, ['a', 'b']);
    await subscription.cancel();
  });

  test('fails with NotAuthenticated without calling when signed out', () async {
    fixture = GrpcFixture(signedIn: false);
    final subscription = listen(open());
    await GrpcFixture.settle();

    expect(errors.single, isA<NotAuthenticated>());
    expect(invoker.calls, isEmpty);
    await subscription.cancel();
  });

  test('UNAUTHENTICATED before the first response reopens once with the '
      'same request', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].responses.add('a');
    await GrpcFixture.settle();

    expect(invoker.calls.map((call) => call.authorization), [
      'Bearer t0',
      'Bearer t1',
    ]);
    expect(invoker.calls[1].sent, ['ping']);
    expect(invoker.calls[0].cancelled, isTrue);
    expect(received, ['a']);
    expect(errors, isEmpty);
    await subscription.cancel();
  });

  test('UNAUTHENTICATED after the first response is surfaced, not '
      'replayed', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();
    invoker.calls.single.responses
      ..add('a')
      ..addError(unauthenticated);
    await GrpcFixture.settle();

    expect(received, ['a']);
    expect(errors, [unauthenticated]);
    expect(invoker.calls, hasLength(1));
    expect(fixture.refresher.calls, 0);
    await subscription.cancel();
  });

  test('a second UNAUTHENTICATED is surfaced after one reopen', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].responses.addError(unauthenticated);
    await GrpcFixture.settle();

    expect(errors, [unauthenticated]);
    expect(invoker.calls, hasLength(2));
    expect(fixture.refresher.calls, 1);
    await subscription.cancel();
  });

  test('a client stream with several requests is never reopened', () async {
    final subscription = listen(
      open(Stream<String>.fromIterable(['one', 'two'])),
    );
    await GrpcFixture.settle();
    invoker.calls.single.responses.addError(unauthenticated);
    await GrpcFixture.settle();

    expect(errors, [unauthenticated]);
    expect(invoker.calls, hasLength(1));
    expect(fixture.refresher.calls, 0);
    await subscription.cancel();
  });

  test('pause and resume reach the call', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();

    subscription.pause();
    expect(invoker.calls.single.responses.isPaused, isTrue);
    subscription.resume();
    expect(invoker.calls.single.responses.isPaused, isFalse);
    await subscription.cancel();
  });

  test('cancelling the subscription cancels the call', () async {
    final subscription = listen(open());
    await GrpcFixture.settle();

    await subscription.cancel();

    expect(invoker.calls.single.cancelled, isTrue);
  });

  test('cancel on the response stream cancels the current call', () async {
    final stream = open();
    final subscription = listen(stream);
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();

    await stream.cancel();
    await GrpcFixture.settle();

    expect(invoker.calls[1].cancelled, isTrue);
    expect(errors.single, isA<grpc.GrpcError>());
    await subscription.cancel();
  });

  test('headers and trailers come from the reopened call', () async {
    invoker.metadataByCall.addAll({
      0: {'call': '0'},
      1: {'call': '1'},
    });
    final stream = open();
    final subscription = listen(stream);
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].responses.add('a');

    expect(await stream.headers, {'call': '1'});
    expect(await stream.trailers, {'call': '1'});
    await subscription.cancel();
  });

  test('single answers with the only response and its headers', () async {
    invoker.metadataByCall[0] = {'call': '0'};
    final response = open().single;
    await GrpcFixture.settle();
    invoker.calls.single.responses.add('a');
    await invoker.calls.single.responses.close();

    expect(await response, 'a');
    expect(await response.headers, {'call': '0'});
  });

  test('concurrent rejected streams share one refresh', () async {
    final first = listen(open());
    final second = listen(open());
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    invoker.calls[1].responses.addError(unauthenticated);
    await GrpcFixture.settle();

    expect(invoker.calls, hasLength(4));
    expect(fixture.refresher.calls, 1);
    await first.cancel();
    await second.cancel();
  });

  test('cancelling before the token arrives never makes a call', () async {
    final stream = open();
    final subscription = listen(stream);

    await subscription.cancel();
    await GrpcFixture.settle();

    expect(invoker.calls, isEmpty);
    expect(await stream.headers, isEmpty);
  });

  test('cancel during the refresh never opens a second call', () async {
    fixture.refresher.gate = Completer<void>();
    final stream = open();
    final subscription = listen(stream);
    await GrpcFixture.settle();
    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();

    await stream.cancel();
    fixture.refresher.gate?.complete();
    await GrpcFixture.settle();

    expect(invoker.calls, hasLength(1));
    expect(
      errors.single,
      isA<grpc.GrpcError>().having(
        (error) => error.code,
        'code',
        grpc.StatusCode.cancelled,
      ),
    );
    await subscription.cancel();
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/token_manager_grpc && dart test test/refresh_interceptor_streaming_test.dart`
Expected: FAIL. The 0.1 streaming path sends without tokens when signed out, replays after the first response, ignores pause, and never reopens with the recorded request, so at least "fails with NotAuthenticated without calling when signed out", "UNAUTHENTICATED after the first response is surfaced, not replayed", "a client stream with several requests is never reopened" and "pause and resume reach the call" fail.

- [ ] **Step 4: Write `AttemptResponseStream`**

Create `packages/token_manager_grpc/lib/src/attempt_response_stream.dart`:

```dart
import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;

import 'attempt_response_future.dart';
import 'call_attempts.dart';
import 'settling_stream.dart';

/// A [grpc.ResponseStream] whose headers, trailers and cancel follow the
/// call that answered, which may be a replay.
final class AttemptResponseStream<R> extends StreamView<R>
    implements grpc.ResponseStream<R> {
  /// Relays [responses], whose calls [attempts] records.
  AttemptResponseStream(Stream<R> responses, CallAttempts attempts)
    : _attempts = attempts,
      super(SettlingStream<R>(responses, attempts).stream);

  final CallAttempts _attempts;

  @override
  grpc.ResponseFuture<R> get single =>
      AttemptResponseFuture<R>(super.single, _attempts);

  @override
  Future<Map<String, String>> get headers => _attempts.headers;

  @override
  Future<Map<String, String>> get trailers => _attempts.trailers;

  @override
  Future<void> cancel() => _attempts.cancel();
}
```

- [ ] **Step 5: Rewrite the interceptor**

Replace the whole of `packages/token_manager_grpc/lib/src/refresh_interceptor.dart` with:

```dart
import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';

import 'attempt_response_future.dart';
import 'attempt_response_stream.dart';
import 'call_attempts.dart';
import 'refresh_interceptor_delegate.dart';
import 'request_log.dart';

/// A gRPC client interceptor that sends calls with valid tokens and replays
/// a call once when the server rejects its tokens.
///
/// Unary calls go through [TokenManager.authorize] and streaming calls
/// through [TokenManager.authorizeStream]. A call fails with
/// `NotAuthenticated` when there are no tokens. A streaming call is made
/// again only before its first response, and only when its request stream
/// ended after at most one request.
class RefreshInterceptor<T> implements grpc.ClientInterceptor {
  /// Creates an interceptor that takes tokens from [manager] and attaches
  /// them with [delegate].
  const RefreshInterceptor({
    required TokenManager<T> manager,
    required RefreshInterceptorDelegate<T> delegate,
  }) : _manager = manager,
       _delegate = delegate;

  final TokenManager<T> _manager;
  final RefreshInterceptorDelegate<T> _delegate;

  @override
  grpc.ResponseFuture<R> interceptUnary<Q, R>(
    grpc.ClientMethod<Q, R> method,
    Q request,
    grpc.CallOptions options,
    grpc.ClientUnaryInvoker<Q, R> invoker,
  ) {
    final attempts = CallAttempts();
    final response = _manager.authorize<R>(
      (tokens) => attempts.unary(
        () => invoker(method, request, _withTokens(options, tokens)),
      ),
      isAuthFailure: _isAuthFailure,
    );
    return AttemptResponseFuture<R>(response, attempts);
  }

  @override
  grpc.ResponseStream<R> interceptStreaming<Q, R>(
    grpc.ClientMethod<Q, R> method,
    Stream<Q> requests,
    grpc.CallOptions options,
    grpc.ClientStreamingInvoker<Q, R> invoker,
  ) {
    final attempts = CallAttempts();
    final log = RequestLog<Q>(requests);
    final responses = _manager.authorizeStream<R>(
      (tokens) => attempts.streaming(
        () => invoker(method, log.next(), _withTokens(options, tokens)),
      ),
      isAuthFailure: (error) => log.isReplayable && _isAuthFailure(error),
    );
    return AttemptResponseStream<R>(responses, attempts);
  }

  bool _isAuthFailure(Object error) =>
      error is grpc.GrpcError && _delegate.shouldRefresh(error);

  grpc.CallOptions _withTokens(grpc.CallOptions options, T tokens) =>
      options.mergedWith(_delegate.buildCallOptions(tokens));
}
```

Then delete the 0.1 stream wrapper:

```bash
git rm packages/token_manager_grpc/lib/src/async_response_stream.dart
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/token_manager_grpc && dart test`
Expected: PASS (45 tests: 8 + 6 + 5 + 12 + 14).

Also confirm the old patterns are gone:

```bash
grep -rn "await for\|ignore_for_file\|catch (\|waitForFresh\|executeRefresh" packages/token_manager_grpc/lib
```

Expected: no output.

- [ ] **Step 7: Gate and commit**

```bash
cd /home/genius/projects/dart_token_manager
dart format packages && dart format --output=none --set-exit-if-changed packages
dart analyze packages
git add packages/token_manager_grpc/lib packages/token_manager_grpc/test
git commit -m "feat(token_manager_grpc)!: relay streaming calls through TokenManager.authorizeStream

A streaming call is reopened only before its first response and only when its
request stream ended after one request; pause, resume and cancel reach the
call; headers, trailers and cancel follow the reopened call.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Size-limits ratchet, docs, example and 0.2.0

**Files:**
- Create: `packages/token_manager_grpc/test/helpers/size_limits.dart` (copied), `packages/token_manager_grpc/test/quality/size_limits_test.dart` (copied)
- Modify: `packages/token_manager_grpc/pubspec.yaml`, `packages/token_manager_grpc/CHANGELOG.md`, `packages/token_manager_grpc/README.md`, `packages/token_manager_grpc/example/main.dart`

**Interfaces:**
- Consumes: the finished package from Tasks 2-6.
- Produces: the ratchet test in the grpc package (empty allowlists), version `0.2.0`, docs and a runnable example on the new API.

**Ratchet decision.** The ratchet is per package (`SizeLimits('.')` measures the package `dart test` runs in). The grpc package gets a byte-for-byte copy of the core's `test/helpers/size_limits.dart` and `test/quality/size_limits_test.dart`, with all three allowlists empty, because every grpc file and method is within its limit after Task 6 (largest lib file `call_attempts.dart`, about 125 lines; largest method under 20 lines). It is added only now because the 0.1 methods `interceptUnary` (43 lines) and `interceptStreaming` (47) would have needed allowlist entries, and new entries are never added. A shared dev-only workspace package for the helper was rejected: it would need workspace and CI changes that collide with the concurrent adapter branches; the duplication can be folded later.

- [ ] **Step 1: Copy the ratchet**

```bash
cd /home/genius/projects/dart_token_manager
mkdir -p packages/token_manager_grpc/test/quality
cp packages/token_manager/test/helpers/size_limits.dart packages/token_manager_grpc/test/helpers/size_limits.dart
cp packages/token_manager/test/quality/size_limits_test.dart packages/token_manager_grpc/test/quality/size_limits_test.dart
grep -n "_fileAllowlist =\|_permanent =\|_methodAllowlist =" packages/token_manager_grpc/test/quality/size_limits_test.dart
```

Expected: the three constants are `{}` (empty). If the core's copy has entries by then, empty them in the grpc copy.

- [ ] **Step 2: Run the ratchet**

Run: `cd packages/token_manager_grpc && dart test test/quality/size_limits_test.dart`
Expected: PASS (2 tests). A failure names the file or method over its limit: split it, never allowlist it.

- [ ] **Step 3: Commit the ratchet**

```bash
cd /home/genius/projects/dart_token_manager
git add packages/token_manager_grpc/test/helpers/size_limits.dart packages/token_manager_grpc/test/quality/size_limits_test.dart
git commit -m "test(token_manager_grpc): enforce the size limits with a ratchet

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Bump the version**

In `packages/token_manager_grpc/pubspec.yaml` change `version: 0.1.0` to `version: 0.2.0`. The `token_manager: ^0.2.0` constraint is already in place (Task 1).

- [ ] **Step 5: Write the CHANGELOG entry**

Insert at the top of `packages/token_manager_grpc/CHANGELOG.md`:

```markdown
## 0.2.0 - Unreleased

### Changed
- Requires `token_manager` ^0.2.0. `RefreshInterceptor` sends unary calls
  through `TokenManager.authorize` and streaming calls through
  `TokenManager.authorizeStream`.
- `RefreshInterceptorDelegate.shouldRefresh` is now called: it decides which
  `GrpcError` means the server rejected the tokens (default:
  `UNAUTHENTICATED`).

### Fixed
- A rejected call no longer forces a refresh when another call already
  refreshed the tokens; concurrent rejections share one refresh.
- A call is replayed at most once.
- A streaming call is no longer replayed after it delivered a response, so a
  response is never delivered twice.
- A streaming call no longer listens to a single-subscription request stream
  a second time.
- `cancel()` reaches the call in flight and, during a refresh, prevents the
  replay; pause and resume reach the call.
- Errors on the `headers` and `trailers` futures no longer escape as uncaught
  zone errors.

### Removed
- The internal `AsyncResponseFuture` and `AsyncResponseStream` (never
  exported).

### Behaviour changes
- Signed out: a call fails with `NotAuthenticated` and is not sent. 0.1 sent
  it without credentials.
- A failed refresh is the call's error: `InvalidGrant` (the session ended and
  is signed out) or `Transient`. 0.1 swallowed it and replayed with the old
  tokens.
- A streaming call is reopened only before its first response, and only when
  its request stream ended after at most one request (server-streaming calls
  from generated code). Client-streaming and bidirectional calls surface
  `UNAUTHENTICATED` without a refresh.
- A streaming call is made when its response stream is listened to; a stream
  that is never listened to sends nothing.
- `headers` and `trailers` follow the call that answered. For a streaming
  call they resolve when the first response, error or end arrives, or on
  cancel; for a unary call once it completes. Without any call (signed out,
  or cancelled before the token arrived) they are empty maps. 0.1 forwarded
  the first call's headers.
- Only `Exception`s are handled; an `Error` thrown by the delegate or an
  invoker propagates.
- `buildCallOptions` is never called with `null`.
```

- [ ] **Step 6: Rewrite the README**

Replace `packages/token_manager_grpc/README.md` with:

````markdown
# token_manager_grpc

[![Pub Version](https://img.shields.io/pub/v/token_manager_grpc.svg)](https://pub.dev/packages/token_manager_grpc)

A gRPC client interceptor for [`token_manager`](https://pub.dev/packages/token_manager).
It attaches valid tokens to every call, and when the server rejects them it
refreshes them once (shared by all concurrent calls) and replays the call once.

## Installation

```yaml
dependencies:
  token_manager: ^0.2.0
  token_manager_grpc: ^0.2.0
```

## Usage

```dart
import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const BearerDelegate();

  @override
  grpc.CallOptions buildCallOptions(TokenSet? tokens) => grpc.CallOptions(
    metadata: {
      if (tokens != null) 'authorization': 'Bearer ${tokens.accessToken}',
    },
  );
}

final manager = TokenManager<TokenSet>.create(
  store: InMemoryTokenStore<TokenSet>(), // or a persistent TokenStore
  refresher: MyRefresher(), // implements TokenRefresher<TokenSet>
  info: const TokenSetInfo(),
);

final client = GreeterClient( // your generated client
  channel,
  interceptors: [
    RefreshInterceptor<TokenSet>(
      manager: manager,
      delegate: const BearerDelegate(),
    ),
  ],
);
```

Override `shouldRefresh` in the delegate when your server reports rejected
tokens with another status than `UNAUTHENTICATED`.

## How calls are replayed

- Without tokens a call fails with `NotAuthenticated` and is not sent.
- A unary call rejected by `shouldRefresh` is replayed once with refreshed
  tokens. A second rejection, or any other error, reaches the caller.
- A streaming call is reopened once only if it was rejected before its first
  response and its request stream ended after at most one request (the shape
  of a server-streaming call). After the first response an error is passed on;
  listen to `manager.states` to resubscribe. Client-streaming and
  bidirectional calls are never reopened.
- If the refresh fails, the call fails with `InvalidGrant` (the session ended)
  or `Transient` (try again later).
- `headers`, `trailers` and `cancel()` follow the call that answered, which may
  be the replay. Pause, resume and cancel reach the gRPC call.

## Migrating from 0.1

The interceptor and delegate keep their names and constructors. Create the
manager with `TokenManager.create`; `initialize()` is no longer needed. See
`CHANGELOG.md` for the behaviour changes.

For a runnable example, see `example/main.dart`.
````

- [ ] **Step 7: Rewrite the example**

Replace `packages/token_manager_grpc/example/main.dart` with:

```dart
import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

final class _ExampleRefresher implements TokenRefresher<TokenSet> {
  const _ExampleRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    // Exchange current.refreshToken with your auth server here.
    return TokenSet(
      accessToken: 'new-access-token',
      refreshToken: 'new-refresh-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

final class _BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const _BearerDelegate();

  @override
  grpc.CallOptions buildCallOptions(TokenSet? tokens) => grpc.CallOptions(
    metadata: {
      if (tokens != null) 'authorization': 'Bearer ${tokens.accessToken}',
    },
  );
}

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: const _ExampleRefresher(),
    info: const TokenSetInfo(),
  );
  await manager.setTokens(
    TokenSet(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );

  final channel = grpc.ClientChannel(
    'localhost',
    port: 50051,
    options: const grpc.ChannelOptions(
      credentials: grpc.ChannelCredentials.insecure(),
    ),
  );
  // Pass the same interceptors to your generated client, for example
  // `GreeterClient(channel, interceptors: [interceptor])`. Every call then
  // carries a valid token and is replayed once after UNAUTHENTICATED.
  final client = grpc.Client(
    channel,
    interceptors: [
      RefreshInterceptor<TokenSet>(
        manager: manager,
        delegate: const _BearerDelegate(),
      ),
    ],
  );
  stdout.writeln('Client ready: ${client.runtimeType}');

  await channel.shutdown();
  await manager.dispose();
}
```

Run: `cd packages/token_manager_grpc && dart run example/main.dart`
Expected: prints `Client ready: Client` and exits 0 (no connection is opened: no call is made).

- [ ] **Step 8: Final gate**

```bash
cd /home/genius/projects/dart_token_manager
dart format packages && dart format --output=none --set-exit-if-changed packages
dart analyze packages
(cd packages/token_manager && dart test)
(cd packages/token_manager_grpc && dart test)
(cd packages/token_manager_grpc && dart pub publish --dry-run)
```

Expected: format changes 0 files, `No issues found!`, both test suites pass (grpc: 47 tests), and the dry run reports no errors (the only acceptable warning is the one about `token_manager ^0.2.0` not yet being on pub.dev, if pub prints it).

- [ ] **Step 9: Commit**

```bash
git add packages/token_manager_grpc/pubspec.yaml packages/token_manager_grpc/CHANGELOG.md packages/token_manager_grpc/README.md packages/token_manager_grpc/example/main.dart
git commit -m "docs(token_manager_grpc): document 0.2.0 and move the example to the new API

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-review

- **Spec coverage.** Section 5 `authorize`/`authorizeStream` usage: Tasks 5, 6. Final-review note on replayed headers and trailers: "Core API decision" plus Tasks 2, 4, 5, 6. Section 6 gRPC bullet (dead `shouldRefresh` made working, errors on `headers`/`trailers` contained, lifecycle reaches the call, no `await for`): Tasks 2, 5, 6. Section 6 streams bullet (reopen only before the first event; client-streaming request streams never replayed): Tasks 3, 6. Section 2 gRPC findings (no compare with rejected token, mid-stream replays, reused single-subscription request stream, cancel not forwarded, pause and resume ignored, uncaught zone errors): all pinned by Task 5/6 tests. Phase 3 "done when": concurrent rejections produce one refresh (unary and streaming tests), pause/resume/cancel reach the source, no `await for` (grep in Task 6). Section 7 rows for gRPC: `RefreshInterceptor` kept source-compatible; the `GrpcTokenInterceptor<T>` rename is not in this plan (open question 1). The spec's "tests on an in-process server" is replaced by invoker-level fakes, as requested for this plan.
- **Placeholder scan.** Every code step carries the full file or the exact replacement.
- **Type consistency.** `CallAttempts.unary`/`streaming`/`settle`/`settleWhenDone`/`cancel`/`headers`/`trailers`, `RequestLog.next`/`isReplayable`, `SettlingStream.stream`, `AttemptResponseFuture(response, attempts)`, `AttemptResponseStream(responses, attempts)`, `GrpcFixture.method`/`settle`/`refresher`/`interceptor`, `CountingRefresher.calls`/`gate`, `FakeUnaryInvoker.calls`/`metadataByCall`/`metadataFailure`/`invoke`, `FakeStreamInvoker.calls`/`metadataByCall`/`invoke`/`closeAll` are used with the same names and types in every task.
- **Verification.** The final code of Tasks 2-7 and the Task 1 tests were run in a scratch copy of the workspace (grpc 5.1.0, Dart 3.13): 47 grpc tests and the new core tests pass, `dart analyze` is clean with the repository's `analysis_options.yaml`, and the intermediate state after Task 5 analyzes cleanly and passes the unary tests.

## Open questions

1. The spec (sections 4 and 7) names the new public class `GrpcTokenInterceptor<T>`, with `RefreshInterceptor<T>` as its deprecated subclass, to avoid the clash with the dio adapter. This plan keeps `RefreshInterceptor<T>` as the only class, as scoped. Add the rename here as a Task 8, or in a follow-up shared with the dio plan?
2. A rejected client-streaming or bidirectional call is surfaced without reporting the rejected token, so the next call may be sent with the same token (a unary or server-streaming call then refreshes). Should the adapter call `manager.validToken(rejected: used)` in that case, ignoring its outcome, so that the next call starts with fresh tokens?
3. Task 1 bumps the core to 0.2.0 and the dio constraint to `^0.2.0`. The dio branch will likely make the same change; identical lines merge cleanly, but whoever merges second should check `packages/token_manager_dio/pubspec.yaml`.

## CI needs (do not edit `ci.yml` in this branch)

- Add a step to the `analyze-test` job after "Test token_manager": name `Test token_manager_grpc`, `working-directory: packages/token_manager_grpc`, `run: dart test`. It runs on every matrix entry (3.10.0 and stable on ubuntu, stable on macOS and Windows); the tests use no network and no platform paths beyond what the ratchet already handles.
- Format and analyze already cover `packages/`, so they include the grpc package with no change.
- Optionally, a publish dry run for `token_manager_grpc` once the `publish-dry-run` workflow exists (phase 5).
