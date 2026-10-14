# token_manager_http: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the new workspace package `packages/token_manager_http` (0.1.0): `HttpTokenClient<T> extends http.BaseClient`, which sends every request with the tokens of a `TokenManager<T>` and replays a rejected `Request` once.

**Architecture:** `HttpTokenClient` wraps an inner `http.Client`. A replayable request (an exact `Request` or an `AbortableRequest`) goes through the core's `TokenManager.authorize`. The send callback sends a fresh copy of the caller's request with the token headers. When `isAuthFailure` accepts the response, the callback reads the body to the end (releasing the connection) and throws it as an internal `RejectedResponse`, which `authorize` treats as the auth failure. A `RejectedResponse` that escapes `authorize` (the replay was rejected too, or there was no replacement token) is turned back into a response with its buffered body. Every other request (`StreamedRequest`, `MultipartRequest`, abortable variants, other subclasses) is sent once as a streamed copy. Its rejection is returned as is, and the rejected tokens are reported to the manager without waiting, so the next request gets new ones. The adapter never refreshes by itself: single flight and compare-and-skip stay in the core.

**Tech Stack:** Dart 3.10+ pub workspace. Runtime dependencies `http: ^1.5.0` and `token_manager: ^0.2.0`; dev dependency `test: ^1.31.0`. No network in tests or the example (`package:http/testing.dart` `MockClient` in the example, a recording fake `BaseClient` in tests).

**Spec:** `docs/superpowers/specs/2026-10-14-token-manager-redesign-design.md` (section 4 package list, section 6 "package:http", roadmap phase 3 item 2). The core API it builds on is `packages/token_manager/lib/src/token_manager.dart` (`authorize`, `validToken({rejected})`) and `lib/src/engine/authorized_call.dart` (the replay rule: replay once; rethrow when the renewed token is identical to the rejected one).

**Rulings (already decided, do not re-litigate):**

- **Default header.** No existing adapter has a default header: dio and gRPC use a delegate, and gql requires `headers: Map<String, String> Function(T tokens)`. `HttpTokenClient` takes the same gql-style `headers` function but makes it optional. When it is omitted, a `TokenSet` is sent as `Authorization: Bearer <accessToken>`. For any other `T` the constructor throws `ArgumentError`, because a generic `T` has no access token. Error messages never include token values.
- **Parameters.** The constructor is `HttpTokenClient({required TokenManager<T> manager, required Client inner, Map<String, String> Function(T tokens)? headers, bool Function(BaseResponse response)? isAuthFailure, bool Function(BaseRequest request)? shouldAuthorize})`, exactly the 5-parameter limit. `isAuthFailure` defaults to `statusCode == 401`, and `shouldAuthorize` defaults to every request.
- **What is replayed.** Only an exact `Request` or an `AbortableRequest` (body in memory). A subclass of `Request` may build its body in `finalize`, so it is sent once, like `StreamedRequest`, `MultipartRequest`, `AbortableStreamedRequest`, `AbortableMultipartRequest` and any other `BaseRequest`.
- **The caller's request is never changed.** Every attempt sends a copy. A replayable `Request` is copied field by field and stays unsent. Any other request is finalized (as sending it would do) and its body is streamed into a new `StreamedRequest` (or `AbortableStreamedRequest`). The caller's headers never get the token header. Abort triggers are kept on the copies.
- **Draining.** A rejected response from a replayable request is read to the end before the replay is sent, so its connection is released. When no replay follows (the replay is rejected too, or there is no replacement token), the caller gets the rejected response with its body served from memory. A rejected response from a request that is sent once is returned untouched (not read).
- **Reporting.** A rejected send-once request reports its tokens with `unawaited(manager.validToken(rejected: used))` and swallows exceptions, like `GrpcTokenInterceptor._reportRejected`. The caller already has the response; an `InvalidGrant` still ends the session through the manager.
- **Errors are not wrapped.** `NotAuthenticated`, `InvalidGrant` and `Transient` come out of `send` (and `get`, `post`, ...) unchanged. A network error (`ClientException`) from the inner client, including one while the rejected body is read, propagates and is never replayed.
- **Ownership.** `close()` closes the inner client exactly once. It never disposes the `TokenManager`, because the client does not own it. A request after `close()` throws `ClientException('HttpTokenClient is closed.', url)` without asking the manager for tokens.
- **http floor `^1.5.0`.** 1.5.0 (2025-08-07, SDK ^3.4.0) added `Abortable`, `AbortableRequest` and `AbortableStreamedRequest`, which the copies need to keep the abort trigger. `BaseResponseWithUrl` exists since 1.2.0. The latest version is 1.6.0 (checked on pub.dev 2026-10-14). `StreamedResponseV2` is not exported by `package:http`, so the buffered response keeps the URL through a private class that implements `BaseResponseWithUrl`.

## Global Constraints

- Branch `feat/token-manager-http` (worktree based on `fec832e`); never commit to `main`. Run git from the repository root.
- Every commit message uses Conventional Commits with the package scope (`build(token_manager_http): ...`, `feat(token_manager_http): ...`, `docs(token_manager_http): ...`, `build: ...`) and ends with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Package pubspec: `version: 0.1.0`, `resolution: workspace`, `environment: sdk: ^3.10.0`, the same `repository`/`homepage`/`issue_tracker` as the other packages, **no `publish_to`**.
- Runtime dependencies are exactly `http: ^1.5.0` and `token_manager: ^0.2.0`; dev dependencies exactly `test: ^1.31.0`. Do not change the version or dependencies of any other package.
- The root `pubspec.yaml` workspace list gains `packages/token_manager_http` after `packages/token_manager_grpc` (sorted).
- Code rules (CLAUDE.md): object-oriented, no top-level functions except `main` in `example/` and in tests; no `!`, no `dynamic`; every `catch` has an `on` clause and `Error` is never caught; positive boolean names, no positional `bool` parameters; `///` docs with a one-sentence summary and `[brackets]`; `late` needs a comment; imports inside the package are relative; the barrel uses `export 'src/x.dart' show A;`, one per line, sorted. Never consume a stream with `await for` in `lib/`.
- Never add `// ignore:` without a reason; never remove a lint.
- Size limits: lib file 300 lines, test file 500, method 40, parameters 5, nesting 3, about 15 members per class, one public class per file, no `utils`/`helpers`/`common` in `lib/`, no `part`. `test/quality/size_limits_test.dart` is a ratchet with empty allowlists that must stay empty.
- At the end of every task, from the repository root: `dart format packages` changes 0 files on a second run, `dart analyze packages` prints `No issues found!`, and `cd packages/token_manager_http && dart test` passes.
- Tests ship in the same commit as the code; no network; one behaviour per test, named after the behaviour; set-up longer than about five lines goes into a helper.
- Public API additions get a bullet in `packages/token_manager_http/CHANGELOG.md` under `## 0.1.0` in the same commit.
- Do not touch `packages/token_manager`, `packages/token_manager_dio`, `packages/token_manager_grpc` or `packages/token_manager_gql`.
- All code, comments and docs are in English.

## Review Focus

These inputs follow from the rulings but no happy-path test covers them. Each one has a pinning test in the task named in brackets.

1. The caller's request already has an `Authorization` header (stale, or set by another layer): the token header must win on the wire, in any letter case, and the caller's map must keep its own value. [Task 2: `the token header replaces the same header in any case`; Task 3: `the token header replaces a header the caller set`]
2. The 401's body stream fails while it is being read (connection reset): the call fails with that `ClientException`, nothing is replayed, and no refresh starts. [Task 4: `a 401 whose body fails to arrive fails the call unreplayed`]
3. A `Content-Type` names a charset Dart does not know (`charset=x-unknown`), or names a known one in upper case: the copy must still be built, and its header must stay byte-identical. [Task 2: `copies a request whose charset is unknown`, `keeps a content type that names its charset as it was`]
4. The replay itself fails with a network error: the caller gets that error, not the earlier 401. [Task 4: `a network error during the replay reaches the caller`]
5. A request that cannot be replayed is rejected while the refresh it triggers fails terminally: the call still returns the 401 (no uncaught async error), and the session ends. [Task 3: `a terminal failure of that refresh ends the session without failing the call`]

---

## File structure

Created in `packages/token_manager_http/`:

| File | Responsibility |
|---|---|
| `pubspec.yaml` | package metadata, the `http ^1.5.0` floor and its reason |
| `.gitignore`, `LICENSE` | copied from `packages/token_manager_gql/` |
| `CHANGELOG.md` | `## 0.1.0`, one bullet per public behaviour |
| `README.md` | usage, what is replayed, anonymous requests, headers and auth failures, errors, closing, testing, constraints |
| `dartdoc_options.yaml` | categories `getting-started`, `replay`, `testing` |
| `doc/getting_started.md`, `doc/replay.md`, `doc/testing.md` | the category guides |
| `example/main.dart` | runnable example on `MockClient` (no network) |
| `lib/token_manager_http.dart` | the only public barrel |
| `lib/src/http_token_client.dart` | `HttpTokenClient<T>` |
| `lib/src/request_copies.dart` | `RequestCopies` (internal): which requests replay, and the copies that are sent |
| `lib/src/rejected_response.dart` | `RejectedResponse` (internal): a rejected response read into memory, thrown inside `authorize` |
| `test/helpers/size_limits.dart` | verbatim copy of the ratchet helper |
| `test/helpers/counting_refresher.dart` | verbatim copy from `token_manager_gql` |
| `test/helpers/fake_answer.dart` | `FakeAnswer`: status, body text, optional body failure |
| `test/helpers/sent_request.dart` | `SentRequest`: a request the fake received, with its body read |
| `test/helpers/recording_client.dart` | `RecordingClient`: fake inner `BaseClient` |
| `test/helpers/client_fixture.dart` | `ClientFixture`: manager + refresher + fake + client |
| `test/quality/size_limits_test.dart` | the ratchet, empty allowlists |
| `test/request_copies_test.dart` | copying rules |
| `test/http_token_client_test.dart` | headers, anonymous requests, streamed bodies, send-once path |
| `test/rejected_response_test.dart` | buffering a rejected response |
| `test/http_token_client_replay_test.dart` | replay, single flight, failures, `isAuthFailure` |
| `test/http_token_client_close_test.dart` | `close()` and ownership |

Modified: root `pubspec.yaml`, `.github/workflows/ci.yml`, `.github/workflows/publish.yml`, `docs/releasing.md`, root `README.md`.

---

### Task 1: Scaffold the package and its size-limits ratchet

**Files:**
- Modify: `pubspec.yaml` (root, `workspace:` list)
- Create: `packages/token_manager_http/pubspec.yaml`
- Create: `packages/token_manager_http/.gitignore` (copy), `packages/token_manager_http/LICENSE` (copy)
- Create: `packages/token_manager_http/CHANGELOG.md`
- Create: `packages/token_manager_http/lib/token_manager_http.dart`
- Create: `packages/token_manager_http/test/helpers/size_limits.dart` (copy)
- Test: `packages/token_manager_http/test/quality/size_limits_test.dart` (copy)

**Interfaces:**
- Consumes: `packages/token_manager_gql/test/helpers/size_limits.dart` (`SizeLimits(String packageRoot)`, `fileFailures({required Map<String, int> allowlist, required Set<String> permanent})`, `methodFailures({required Map<String, int> allowlist})`), identical in every package and copied verbatim.
- Produces: a resolvable workspace package `token_manager_http` with the barrel `package:token_manager_http/token_manager_http.dart` (no exports yet) and a `CHANGELOG.md` whose `## 0.1.0` section later tasks append bullets to.

- [ ] **Step 1: Add the package to the workspace**

In the root `pubspec.yaml`, replace the `workspace:` list with:

```yaml
workspace:
- packages/token_manager
- packages/token_manager_dio
- packages/token_manager_gql
- packages/token_manager_grpc
- packages/token_manager_http
```

- [ ] **Step 2: Write the package pubspec**

Create `packages/token_manager_http/pubspec.yaml`:

```yaml
name: token_manager_http
description: A package:http client that attaches token_manager tokens to requests and replays a request once after an auth failure.
version: 0.1.0
repository: https://github.com/4akloon/dart_token_manager
homepage: https://github.com/4akloon/dart_token_manager
issue_tracker: https://github.com/4akloon/dart_token_manager/issues
topics:
- http
- authentication
- oauth

environment:
sdk: ^3.10.0

resolution: workspace

# http 1.5.0 added Abortable, AbortableRequest and AbortableStreamedRequest:
# the client keeps the abort trigger of a request on the copy it sends.
dependencies:
http: ^1.5.0
token_manager: ^0.2.0

dev_dependencies:
test: ^1.31.0
```

- [ ] **Step 3: Copy the boilerplate and the ratchet**

```bash
mkdir -p packages/token_manager_http/lib/src packages/token_manager_http/test/helpers packages/token_manager_http/test/quality
cp packages/token_manager_gql/.gitignore packages/token_manager_http/.gitignore
cp packages/token_manager_gql/LICENSE packages/token_manager_http/LICENSE
cp packages/token_manager_gql/test/helpers/size_limits.dart packages/token_manager_http/test/helpers/size_limits.dart
cp packages/token_manager_gql/test/quality/size_limits_test.dart packages/token_manager_http/test/quality/size_limits_test.dart
```

Both test files are copied unchanged. `size_limits_test.dart` measures `SizeLimits('.')`, the package that runs `dart test`, and its three allowlists (`_fileAllowlist`, `_permanent`, `_methodAllowlist`) stay empty. Never add entries.

- [ ] **Step 4: Write the barrel and the changelog**

Create `packages/token_manager_http/lib/token_manager_http.dart`:

```dart
/// A `package:http` client that attaches token_manager tokens to requests and
/// replays a request once after an auth failure.
///
/// {@category getting-started}
library;
```

Create `packages/token_manager_http/CHANGELOG.md`:

```markdown
# Changelog

## 0.1.0

Initial release of the `package:http` adapter for token_manager.
```

- [ ] **Step 5: Resolve and check the version**

Run: `dart pub get`
Expected: succeeds. Then run `grep -A3 '^  http:' pubspec.lock`
Expected: `version: "1.6.0"` (or a newer 1.x).

- [ ] **Step 6: Run the ratchet**

Run: `cd packages/token_manager_http && dart test`
Expected: PASS, 2 tests (`no file is over its size limit unless it is allowlisted`, `no method is over 40 lines unless it is allowlisted`).

- [ ] **Step 7: Format and analyze**

Run: `dart format packages && dart format packages && dart analyze packages`
Expected: the second format run reports `0 changed`; analyze prints `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml packages/token_manager_http
git commit -m "build(token_manager_http): scaffold the package and its size ratchet

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: RequestCopies

**Files:**
- Create: `packages/token_manager_http/lib/src/request_copies.dart`
- Test: `packages/token_manager_http/test/request_copies_test.dart`

**Interfaces:**
- Consumes: `package:http/http.dart` (`BaseRequest`, `Request`, `AbortableRequest`, `StreamedRequest`, `AbortableStreamedRequest`, `Abortable`, `MultipartRequest`).
- Produces: `final class RequestCopies` (internal, not exported) with
- `const RequestCopies()`
- `Request? asReplayable(BaseRequest request)`: the request when it is an `AbortableRequest` or exactly a `Request`, else `null`
- `Request copyOf(Request original, Map<String, String> headers)`: an unsent copy with `headers` added; `original` untouched and unsent
- `StreamedRequest streamOf(BaseRequest original, Map<String, String> headers)`: finalizes `original` and streams its body into a new request with `headers` added

- [ ] **Step 1: Write the failing tests**

Create `packages/token_manager_http/test/request_copies_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager_http/src/request_copies.dart';

/// A [Request] subclass, which may build its body in `finalize`.
final class _SignedRequest extends Request {
_SignedRequest(super.method, super.url);
}

void main() {
const copies = RequestCopies();
final url = Uri.parse('https://api.example.com/items');
const token = {'Authorization': 'Bearer t'};

group('asReplayable', () {
  test('accepts a Request', () {
    final request = Request('GET', url);

    expect(copies.asReplayable(request), same(request));
  });

  test('accepts an AbortableRequest', () {
    final request = AbortableRequest('GET', url);

    expect(copies.asReplayable(request), same(request));
  });

  test('rejects a StreamedRequest', () {
    expect(copies.asReplayable(StreamedRequest('POST', url)), isNull);
  });

  test('rejects a MultipartRequest', () {
    expect(copies.asReplayable(MultipartRequest('POST', url)), isNull);
  });

  test('rejects another subclass of Request', () {
    expect(copies.asReplayable(_SignedRequest('GET', url)), isNull);
  });
});

group('copyOf', () {
  test('copies the method, url, headers and body', () {
    final original = Request('PUT', url)
      ..headers['X-Trace'] = '1'
      ..body = 'hello';

    final copy = copies.copyOf(original, token);

    expect(copy.method, 'PUT');
    expect(copy.url, url);
    expect(copy.headers['x-trace'], '1');
    expect(copy.headers['content-type'], original.headers['content-type']);
    expect(copy.body, 'hello');
  });

  test('adds the token header and leaves the original unchanged', () {
    final original = Request('GET', url);

    final copy = copies.copyOf(original, token);

    expect(copy.headers['authorization'], 'Bearer t');
    expect(original.headers, isEmpty);
    expect(original.finalized, isFalse);
  });

  test('the token header replaces the same header in any case', () {
    final original = Request('GET', url)
      ..headers['authorization'] = 'Bearer stale';

    final copy = copies.copyOf(original, token);

    expect(copy.headers, hasLength(1));
    expect(copy.headers['Authorization'], 'Bearer t');
    expect(original.headers['authorization'], 'Bearer stale');
  });

  test('copies the redirect and connection settings', () {
    final original = Request('GET', url)
      ..followRedirects = false
      ..maxRedirects = 2
      ..persistentConnection = false;

    final copy = copies.copyOf(original, token);

    expect(copy.followRedirects, isFalse);
    expect(copy.maxRedirects, 2);
    expect(copy.persistentConnection, isFalse);
  });

  test('copies an encoding that the content type does not name', () {
    final original = Request('POST', url)
      ..encoding = latin1
      ..bodyBytes = [0xE9];

    final copy = copies.copyOf(original, token);

    expect(copy.encoding, latin1);
    expect(copy.headers.containsKey('content-type'), isFalse);
    expect(copy.bodyBytes, [0xE9]);
  });

  test('keeps a content type that names its charset as it was', () {
    final original = Request('POST', url)
      ..headers['content-type'] = 'text/plain; charset=UTF-8';

    final copy = copies.copyOf(original, token);

    expect(copy.headers['content-type'], 'text/plain; charset=UTF-8');
  });

  test('copies a request whose charset is unknown', () {
    final original = Request('POST', url)
      ..headers['content-type'] = 'text/plain; charset=x-unknown'
      ..bodyBytes = [1, 2];

    final copy = copies.copyOf(original, token);

    expect(copy.headers['content-type'], 'text/plain; charset=x-unknown');
    expect(copy.bodyBytes, [1, 2]);
  });

  test('keeps the abort trigger of an AbortableRequest', () {
    final trigger = Completer<void>().future;
    final original = AbortableRequest('GET', url, abortTrigger: trigger);

    final copy = copies.copyOf(original, token);

    expect(
      copy,
      isA<AbortableRequest>().having(
        (request) => request.abortTrigger,
        'abortTrigger',
        same(trigger),
      ),
    );
  });
});

group('streamOf', () {
  test('streams the body of a StreamedRequest with the token header', () async {
    final original = StreamedRequest('POST', url)
      ..headers['X-Trace'] = '1'
      ..contentLength = 5;
    original.sink.add(utf8.encode('hello'));
    unawaited(original.sink.close());

    final copy = copies.streamOf(original, token);

    expect(copy.headers['authorization'], 'Bearer t');
    expect(copy.headers['x-trace'], '1');
    expect(copy.contentLength, 5);
    expect(await copy.finalize().bytesToString(), 'hello');
    expect(original.headers.containsKey('authorization'), isFalse);
  });

  test('keeps the multipart content type and body', () async {
    final original = MultipartRequest('POST', url)..fields['name'] = 'ada';

    final copy = copies.streamOf(original, token);

    expect(
      copy.headers['content-type'],
      startsWith('multipart/form-data; boundary='),
    );
    expect(copy.contentLength, original.contentLength);
    expect(await copy.finalize().bytesToString(), contains('ada'));
  });

  test('keeps the abort trigger of an abortable request', () {
    final trigger = Completer<void>().future;
    final original = AbortableStreamedRequest(
      'POST',
      url,
      abortTrigger: trigger,
    );
    unawaited(original.sink.close());

    final copy = copies.streamOf(original, token);

    expect(
      copy,
      isA<AbortableStreamedRequest>().having(
        (request) => request.abortTrigger,
        'abortTrigger',
        same(trigger),
      ),
    );
  });

  test('forwards an error of the original body', () async {
    final original = StreamedRequest('POST', url);
    original.sink.addError(const FormatException('broken'));
    unawaited(original.sink.close());

    final copy = copies.streamOf(original, token);

    await expectLater(copy.finalize().toBytes(), throwsFormatException);
  });
});
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/token_manager_http && dart test test/request_copies_test.dart`
Expected: FAIL to compile: `Target of URI doesn't exist: 'package:token_manager_http/src/request_copies.dart'`.

- [ ] **Step 3: Implement RequestCopies**

Create `packages/token_manager_http/lib/src/request_copies.dart`:

```dart
import 'dart:async';

import 'package:http/http.dart';

/// Builds the requests `HttpTokenClient` sends in place of the caller's, so
/// the caller's request never gets the token header.
final class RequestCopies {
/// Creates the helper.
const RequestCopies();

/// Returns [request] as a [Request] when it can be copied and sent again,
/// or `null` when its body can be sent only once.
///
/// A subclass of [Request] other than [AbortableRequest] may build its body
/// in `finalize`, so it is sent once like a streamed request.
Request? asReplayable(BaseRequest request) => switch (request) {
  final AbortableRequest abortable => abortable,
  final Request plain when plain.runtimeType == Request => plain,
  _ => null,
};

/// Returns a copy of [original] with [headers] added.
///
/// [original] stays unchanged and unsent, so it can be copied again for a
/// replay. An abort trigger is kept.
Request copyOf(Request original, Map<String, String> headers) {
  final copy = switch (original) {
    final AbortableRequest abortable => AbortableRequest(
      original.method,
      original.url,
      abortTrigger: abortable.abortTrigger,
    ),
    _ => Request(original.method, original.url),
  };
  _copyEncoding(original, copy);
  copy
    ..headers.addAll(original.headers)
    ..headers.addAll(headers)
    ..bodyBytes = original.bodyBytes
    ..followRedirects = original.followRedirects
    ..maxRedirects = original.maxRedirects
    ..persistentConnection = original.persistentConnection;
  return copy;
}

/// Returns a request that streams the body of [original] with [headers]
/// added.
///
/// [original] is finalized, as sending it would, but its headers are left
/// unchanged. An abort trigger is kept.
StreamedRequest streamOf(BaseRequest original, Map<String, String> headers) {
  // Finalize first: a MultipartRequest sets its content type there.
  final body = original.finalize();
  final copy = switch (original) {
    Abortable(:final abortTrigger) => AbortableStreamedRequest(
      original.method,
      original.url,
      abortTrigger: abortTrigger,
    ),
    _ => StreamedRequest(original.method, original.url),
  };
  copy
    ..headers.addAll(original.headers)
    ..headers.addAll(headers)
    ..contentLength = original.contentLength
    ..followRedirects = original.followRedirects
    ..maxRedirects = original.maxRedirects
    ..persistentConnection = original.persistentConnection;
  unawaited(copy.sink.addStream(body).whenComplete(copy.sink.close));
  return copy;
}

/// Gives [copy] the encoding of [original] while [copy] has no content type
/// yet, so the charset of a copied content type is never rewritten.
void _copyEncoding(Request original, Request copy) {
  try {
    copy.encoding = original.encoding;
  } on FormatException {
    // The content type names a charset Dart does not know; the copied
    // header carries it and the default encoding is never read.
  }
}
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/token_manager_http && dart test`
Expected: PASS (16 new tests plus the 2 ratchet tests).

- [ ] **Step 5: Format and analyze**

Run: `dart format packages && dart format packages && dart analyze packages`
Expected: `0 changed` on the second run; `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add packages/token_manager_http
git commit -m "feat(token_manager_http): copy requests so the caller's request stays unchanged

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: HttpTokenClient: attach tokens and send once

**Files:**
- Create: `packages/token_manager_http/lib/src/http_token_client.dart`
- Modify: `packages/token_manager_http/lib/token_manager_http.dart`
- Modify: `packages/token_manager_http/CHANGELOG.md`
- Create: `packages/token_manager_http/test/helpers/counting_refresher.dart` (copy), `fake_answer.dart`, `sent_request.dart`, `recording_client.dart`, `client_fixture.dart`
- Test: `packages/token_manager_http/test/http_token_client_test.dart`

**Interfaces:**
- Consumes: `RequestCopies` (Task 2): `asReplayable`, `copyOf`, `streamOf`. Core: `TokenManager<T>.validToken({T? rejected})`, `TokenSet.accessToken`, `NotAuthenticated`, `InvalidGrant`.
- Produces:
- `final class HttpTokenClient<T> extends BaseClient` with the constructor `HttpTokenClient({required TokenManager<T> manager, required Client inner, Map<String, String> Function(T tokens)? headers, bool Function(BaseResponse response)? isAuthFailure, bool Function(BaseRequest request)? shouldAuthorize})` and `Future<StreamedResponse> send(BaseRequest request)`. In this task every authorized request is sent once; Task 4 adds the replay.
- Test helpers used by Tasks 4 and 5: `FakeAnswer(int status, [String body = '', Exception? failure])` with `FakeAnswer.ok` (200 `ok`) and `FakeAnswer.unauthorized` (401 `denied`); `SentRequest` (`request`, `body`, `unreadBodies`, `authorization`, `text`); `RecordingClient({FutureOr<FakeAnswer> Function(SentRequest request)? answer})` (`requests`, `closeCalls`; default answer: 401 to `Bearer old`, 200 to anything else); `ClientFixture({bool isSignedIn = true, bool hasRefresher = true, Exception? refreshFailure, FutureOr<FakeAnswer> Function(SentRequest request)? answer})` (`manager`, `refresher`, `inner`, `client`, `clientWith({headers, isAuthFailure, shouldAuthorize})`, `post()`, `static const TokenSet old`, `static final Uri url`).

- [ ] **Step 1: Copy the refresher and write the test helpers**

```bash
cp packages/token_manager_gql/test/helpers/counting_refresher.dart packages/token_manager_http/test/helpers/counting_refresher.dart
```

(`CountingRefresher({Exception? failure})`, `int get calls`, returns `TokenSet(accessToken: 'fresh-<n>')`.)

Create `packages/token_manager_http/test/helpers/fake_answer.dart`:

```dart
/// What the fake inner client answers: a status, a body text, and an
/// optional failure of the body stream.
final class FakeAnswer {
/// Creates an answer whose body fails with [failure] after [body] when it
/// is set.
const FakeAnswer(this.status, [this.body = '', this.failure]);

/// A 200 with the body `ok`.
static const FakeAnswer ok = FakeAnswer(200, 'ok');

/// A 401 with the body `denied`.
static const FakeAnswer unauthorized = FakeAnswer(401, 'denied');

/// The status code.
final int status;

/// The body text.
final String body;

/// What the body stream fails with after [body]; `null` ends it normally.
final Exception? failure;
}
```

Create `packages/token_manager_http/test/helpers/sent_request.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart';

/// A request the fake inner client received, with its body read.
final class SentRequest {
/// Records [request] with its [body], sent while [unreadBodies] earlier
/// response bodies were not read yet.
const SentRequest(this.request, this.body, {required this.unreadBodies});

/// The request as the inner client got it.
final BaseRequest request;

/// The body bytes.
final Uint8List body;

/// How many earlier response bodies were unread when this request was sent.
final int unreadBodies;

/// The `Authorization` header, if any.
String? get authorization => request.headers['authorization'];

/// The body as UTF-8 text.
String get text => utf8.decode(body);
}
```

Create `packages/token_manager_http/test/helpers/recording_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';

import 'fake_answer.dart';
import 'sent_request.dart';

/// An inner client that answers from a callback, records every request and
/// counts [close] calls; it never opens a socket.
final class RecordingClient extends BaseClient {
/// Answers with [answer]; by default 401 to the token `old` and 200 to any
/// other.
RecordingClient({FutureOr<FakeAnswer> Function(SentRequest request)? answer})
  : _answer = answer ?? _byToken;

final FutureOr<FakeAnswer> Function(SentRequest request) _answer;
int _unreadBodies = 0;
int _closeCalls = 0;

/// The requests received, in order.
final List<SentRequest> requests = [];

/// How many times [close] was called.
int get closeCalls => _closeCalls;

@override
Future<StreamedResponse> send(BaseRequest request) async {
  final body = await request.finalize().toBytes();
  final sent = SentRequest(request, body, unreadBodies: _unreadBodies);
  requests.add(sent);
  final answer = await _answer(sent);
  return StreamedResponse(_bodyOf(answer), answer.status, request: request);
}

@override
void close() {
  _closeCalls++;
}

/// A single-subscription body that counts as unread until it is listened
/// to.
Stream<List<int>> _bodyOf(FakeAnswer answer) {
  _unreadBodies++;
  return Stream<List<int>>.multi((listener) {
    _unreadBodies--;
    listener.add(utf8.encode(answer.body));
    final failure = answer.failure;
    if (failure != null) {
      listener.addError(failure);
    }
    unawaited(listener.close());
  });
}

static FakeAnswer _byToken(SentRequest request) =>
    request.authorization == 'Bearer old'
    ? FakeAnswer.unauthorized
    : FakeAnswer.ok;
}
```

Create `packages/token_manager_http/test/helpers/client_fixture.dart`:

```dart
import 'dart:async';

import 'package:http/http.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

import 'counting_refresher.dart';
import 'fake_answer.dart';
import 'recording_client.dart';
import 'sent_request.dart';

/// Wires an [HttpTokenClient] between a [TokenManager] and a
/// [RecordingClient], and builds requests for it.
final class ClientFixture {
/// Creates a fixture whose session holds [old] when [isSignedIn], refreshes
/// through a [CountingRefresher] when [hasRefresher] (which throws
/// [refreshFailure] when it is set), and whose inner client answers with
/// [answer]: by default 401 to the token `old` and 200 to any other.
factory ClientFixture({
  bool isSignedIn = true,
  bool hasRefresher = true,
  Exception? refreshFailure,
  FutureOr<FakeAnswer> Function(SentRequest request)? answer,
}) {
  final refresher = CountingRefresher(failure: refreshFailure);
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(isSignedIn ? old : null),
    refresher: hasRefresher ? refresher : null,
  );
  return ClientFixture._(manager, refresher, RecordingClient(answer: answer));
}

ClientFixture._(this.manager, this.refresher, this.inner)
  : client = HttpTokenClient<TokenSet>(manager: manager, inner: inner);

/// The tokens a signed-in session starts with.
static const TokenSet old = TokenSet(accessToken: 'old');

/// The address of the test requests.
static final Uri url = Uri.parse('https://api.example.com/me');

/// The session's manager.
final TokenManager<TokenSet> manager;

/// The manager's refresher.
final CountingRefresher refresher;

/// The client behind [client].
final RecordingClient inner;

/// The client under test, with the default options.
final HttpTokenClient<TokenSet> client;

/// A client over the same [manager] and [inner] with the given options.
HttpTokenClient<TokenSet> clientWith({
  Map<String, String> Function(TokenSet tokens)? headers,
  bool Function(BaseResponse response)? isAuthFailure,
  bool Function(BaseRequest request)? shouldAuthorize,
}) => HttpTokenClient<TokenSet>(
  manager: manager,
  inner: inner,
  headers: headers,
  isAuthFailure: isAuthFailure,
  shouldAuthorize: shouldAuthorize,
);

/// A JSON POST to [url] with an `X-Trace` header.
Request post() => Request('POST', url)
  ..headers['X-Trace'] = '1'
  ..headers['content-type'] = 'application/json'
  ..body = '{"name":"ada"}';
}
```

- [ ] **Step 2: Write the failing tests**

Create `packages/token_manager_http/test/http_token_client_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

import 'helpers/client_fixture.dart';
import 'helpers/fake_answer.dart';
import 'helpers/recording_client.dart';
import 'helpers/sent_request.dart';

FakeAnswer _alwaysOk(SentRequest request) => FakeAnswer.ok;

StreamedRequest _streamed(String body) {
final request = StreamedRequest('POST', ClientFixture.url);
request.sink.add(utf8.encode(body));
unawaited(request.sink.close());
return request;
}

void main() {
group('with tokens', () {
  test('attaches the bearer header of the current tokens', () async {
    final fixture = ClientFixture(answer: _alwaysOk);

    await fixture.client.get(ClientFixture.url);

    expect(fixture.inner.requests.single.authorization, 'Bearer old');
  });

  test('returns the response of the inner client', () async {
    final fixture = ClientFixture(answer: _alwaysOk);

    final response = await fixture.client.get(ClientFixture.url);

    expect(response.statusCode, 200);
    expect(response.body, 'ok');
  });

  test('sends the method, headers and body of the request', () async {
    final fixture = ClientFixture(answer: _alwaysOk);

    await fixture.client.send(fixture.post());

    final sent = fixture.inner.requests.single;
    expect(sent.request.method, 'POST');
    expect(sent.request.headers['x-trace'], '1');
    expect(sent.text, '{"name":"ada"}');
  });

  test('leaves the caller request without the token header', () async {
    final fixture = ClientFixture(answer: _alwaysOk);
    final request = fixture.post();

    await fixture.client.send(request);

    expect(request.headers.containsKey('authorization'), isFalse);
    expect(request.finalized, isFalse);
  });

  test('the token header replaces a header the caller set', () async {
    final fixture = ClientFixture(answer: _alwaysOk);
    final request = fixture.post()
      ..headers['Authorization'] = 'Bearer stale';

    await fixture.client.send(request);

    expect(fixture.inner.requests.single.authorization, 'Bearer old');
    expect(request.headers['authorization'], 'Bearer stale');
  });
});

group('headers', () {
  test('sends the headers the builder returns', () async {
    final fixture = ClientFixture(answer: _alwaysOk);
    final client = fixture.clientWith(
      headers: (tokens) => {'X-Api-Key': tokens.accessToken},
    );

    await client.get(ClientFixture.url);

    final sent = fixture.inner.requests.single;
    expect(sent.request.headers['x-api-key'], 'old');
    expect(sent.authorization, isNull);
  });

  test('works with any token type that has a headers builder', () async {
    final inner = RecordingClient(answer: _alwaysOk);
    final client = HttpTokenClient<String>(
      manager: TokenManager<String>.create(
        store: InMemoryTokenStore<String>('abc'),
      ),
      inner: inner,
      headers: (tokens) => {'Authorization': 'Token $tokens'},
    );

    await client.get(ClientFixture.url);

    expect(inner.requests.single.authorization, 'Token abc');
  });

  test('needs a headers builder unless the token type is TokenSet', () {
    expect(
      () => HttpTokenClient<String>(
        manager: TokenManager<String>.create(
          store: InMemoryTokenStore<String>(),
        ),
        inner: RecordingClient(),
      ),
      throwsArgumentError,
    );
  });
});

group('without tokens', () {
  test('a request shouldAuthorize declines is sent unchanged', () async {
    final fixture = ClientFixture(isSignedIn: false, answer: _alwaysOk);
    final client = fixture.clientWith(
      shouldAuthorize: (request) => request.url.path != '/login',
    );
    final login = Request('POST', Uri.parse('https://api.example.com/login'));

    await client.send(login);

    expect(fixture.inner.requests.single.request, same(login));
    expect(fixture.inner.requests.single.authorization, isNull);
  });

  test('fails with NotAuthenticated and sends nothing', () async {
    final fixture = ClientFixture(isSignedIn: false, answer: _alwaysOk);

    await expectLater(
      fixture.client.get(ClientFixture.url),
      throwsA(isA<NotAuthenticated>()),
    );
    expect(fixture.inner.requests, isEmpty);
  });
});

group('streamed bodies', () {
  test('a StreamedRequest is sent with the token header', () async {
    final fixture = ClientFixture(answer: _alwaysOk);
    final request = _streamed('chunk');

    await fixture.client.send(request);

    final sent = fixture.inner.requests.single;
    expect(sent.authorization, 'Bearer old');
    expect(sent.text, 'chunk');
    expect(request.headers.containsKey('authorization'), isFalse);
  });

  test('a MultipartRequest keeps its boundary and fields', () async {
    final fixture = ClientFixture(answer: _alwaysOk);
    final request = MultipartRequest('POST', ClientFixture.url)
      ..fields['name'] = 'ada';

    await fixture.client.send(request);

    final sent = fixture.inner.requests.single;
    expect(
      sent.request.headers['content-type'],
      startsWith('multipart/form-data; boundary='),
    );
    expect(sent.text, contains('ada'));
    expect(sent.authorization, 'Bearer old');
  });
});

group('a request sent once', () {
  test('a rejected StreamedRequest is returned as is', () async {
    final fixture = ClientFixture();

    final response = await fixture.client.send(_streamed('chunk'));

    expect(response.statusCode, 401);
    expect(await response.stream.bytesToString(), 'denied');
    expect(fixture.inner.requests, hasLength(1));
  });

  test('a rejected MultipartRequest is returned as is', () async {
    final fixture = ClientFixture();
    final request = MultipartRequest('POST', ClientFixture.url)
      ..fields['name'] = 'ada';

    final response = await fixture.client.send(request);

    expect(response.statusCode, 401);
    expect(fixture.inner.requests, hasLength(1));
  });

  test('its rejection starts a refresh for the next request', () async {
    final fixture = ClientFixture();

    await fixture.client.send(_streamed('chunk'));
    await pumpEventQueue();
    final next = await fixture.client.get(ClientFixture.url);

    expect(fixture.refresher.calls, 1);
    expect(next.statusCode, 200);
    expect(fixture.inner.requests, hasLength(2));
    expect(fixture.inner.requests.last.authorization, 'Bearer fresh-1');
  });

  test(
    'a terminal failure of that refresh ends the session without failing '
    'the call',
    () async {
      final fixture = ClientFixture(refreshFailure: const InvalidGrant());

      final response = await fixture.client.send(_streamed('chunk'));
      await pumpEventQueue();

      expect(response.statusCode, 401);
      expect(await fixture.manager.current(), isNull);
    },
  );
});
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/token_manager_http && dart test test/http_token_client_test.dart`
Expected: FAIL to compile: `Undefined name 'HttpTokenClient'` / the barrel exports nothing.

- [ ] **Step 4: Implement the client**

Create `packages/token_manager_http/lib/src/http_token_client.dart`:

```dart
import 'dart:async';

import 'package:http/http.dart';
import 'package:token_manager/token_manager.dart';

import 'request_copies.dart';

/// An `http` [Client] that sends requests with the tokens of a
/// [TokenManager].
///
/// The client never refreshes by itself: it asks the manager for valid
/// tokens before every request and reports the tokens a server rejected, so
/// concurrent requests share one refresh. Every request is sent as a copy,
/// so the caller's request never gets the token header.
///
/// ```dart
/// final client = HttpTokenClient<TokenSet>(manager: manager, inner: Client());
/// final response = await client.get(Uri.parse('https://api.example.com/me'));
/// ```
///
/// {@category getting-started}
final class HttpTokenClient<T> extends BaseClient {
/// Creates a client that sends through [inner] with the tokens of
/// [manager].
///
/// [headers] turns tokens into request headers; without it a `TokenSet` is
/// sent as `Authorization: Bearer <accessToken>`, and any other token type
/// throws an [ArgumentError]. [isAuthFailure] recognises a rejection, by
/// default status 401. A request for which [shouldAuthorize] returns
/// `false`, such as a login, is sent unchanged without tokens.
HttpTokenClient({
  required TokenManager<T> manager,
  required Client inner,
  Map<String, String> Function(T tokens)? headers,
  bool Function(BaseResponse response)? isAuthFailure,
  bool Function(BaseRequest request)? shouldAuthorize,
}) : _manager = manager,
     _inner = inner,
     _headers = headers ?? _bearer,
     _isAuthFailure = isAuthFailure ?? _isUnauthorized,
     _shouldAuthorize = shouldAuthorize ?? _authorizesAll {
  if (headers == null && T != TokenSet) {
    throw ArgumentError.value(
      headers,
      'headers',
      'is required unless the token type is TokenSet',
    );
  }
}

/// The status that rejects the tokens unless [isAuthFailure] says
/// otherwise.
static const int _unauthorized = 401;

static const RequestCopies _copies = RequestCopies();

final TokenManager<T> _manager;
final Client _inner;
final Map<String, String> Function(T tokens) _headers;
final bool Function(BaseResponse response) _isAuthFailure;
final bool Function(BaseRequest request) _shouldAuthorize;

/// Sends [request] with valid tokens.
///
/// Throws `NotAuthenticated`, `InvalidGrant` or `Transient` when the
/// manager has no tokens to send; the request is then not sent.
@override
Future<StreamedResponse> send(BaseRequest request) async {
  if (!_shouldAuthorize(request)) {
    return _inner.send(request);
  }
  return _sendOnce(request);
}

/// Sends [request] a single time; a rejection is returned as is and its
/// tokens are reported, so the next request gets new ones.
Future<StreamedResponse> _sendOnce(BaseRequest request) async {
  final tokens = await _manager.validToken();
  final response = await _inner.send(_authorized(request, tokens));
  if (_isAuthFailure(response)) {
    unawaited(_reportRejected(tokens));
  }
  return response;
}

/// Returns the copy of [request] that carries the headers of [tokens].
BaseRequest _authorized(BaseRequest request, T tokens) {
  final headers = _headers(tokens);
  return switch (_copies.asReplayable(request)) {
    final Request replayable => _copies.copyOf(replayable, headers),
    null => _copies.streamOf(request, headers),
  };
}

/// Asks the manager to renew [rejected] and ignores the outcome, because
/// the caller already has the rejected response.
Future<void> _reportRejected(T rejected) async {
  try {
    await _manager.validToken(rejected: rejected);
  } on Exception {
    // The caller already has the rejected response; a terminal failure
    // still ends the session inside the manager.
  }
}

static Map<String, String> _bearer(Object? tokens) => switch (tokens) {
  TokenSet(:final accessToken) => {'Authorization': 'Bearer $accessToken'},
  _ => throw StateError('HttpTokenClient needs headers for this token type.'),
};

static bool _isUnauthorized(BaseResponse response) =>
    response.statusCode == _unauthorized;

static bool _authorizesAll(BaseRequest request) => true;
}
```

Replace `packages/token_manager_http/lib/token_manager_http.dart` with:

```dart
/// A `package:http` client that attaches token_manager tokens to requests and
/// replays a request once after an auth failure.
///
/// {@category getting-started}
library;

export 'src/http_token_client.dart' show HttpTokenClient;
```

Append to `packages/token_manager_http/CHANGELOG.md`:

```markdown

- `HttpTokenClient<T>`, a `BaseClient` over an inner `Client` that sends
every request with the headers built from the tokens of a
`TokenManager<T>` (by default `Authorization: Bearer <accessToken>` for
`TokenSet`) and never changes the caller's request. A request that
`shouldAuthorize` declines, such as a login, is sent unchanged without
tokens.
- A streamed or multipart request is sent once. When the server rejects it
(`isAuthFailure`, status 401 by default) the response is returned as is and
the rejected tokens are reported to the manager, so the next request gets
new ones.
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/token_manager_http && dart test`
Expected: PASS (all tests, including 16 in `http_token_client_test.dart`).

- [ ] **Step 6: Format and analyze**

Run: `dart format packages && dart format packages && dart analyze packages`
Expected: `0 changed` on the second run; `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add packages/token_manager_http
git commit -m "feat(token_manager_http): send requests with the manager's tokens

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Replay a rejected Request once, reading the rejected body first

**Files:**
- Create: `packages/token_manager_http/lib/src/rejected_response.dart`
- Modify: `packages/token_manager_http/lib/src/http_token_client.dart` (full content below)
- Modify: `packages/token_manager_http/CHANGELOG.md`
- Test: `packages/token_manager_http/test/rejected_response_test.dart`, `packages/token_manager_http/test/http_token_client_replay_test.dart`

**Interfaces:**
- Consumes: Task 2 `RequestCopies`; Task 3 `HttpTokenClient` and the helpers; core `TokenManager.authorize<R>(Future<R> Function(T tokens) send, {required bool Function(Object error) isAuthFailure})`, which replays once, rethrows when the renewed tokens are identical to the rejected ones, and lets a second failure propagate.
- Produces: `final class RejectedResponse implements Exception` (internal) with `static Future<RejectedResponse> read(StreamedResponse response)`, `static bool matches(Object error)` and `StreamedResponse toResponse()`. `HttpTokenClient.send` now replays a replayable request once.

- [ ] **Step 1: Write the failing tests for RejectedResponse**

Create `packages/token_manager_http/test/rejected_response_test.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager_http/src/rejected_response.dart';

StreamedResponse _rejected({Stream<List<int>>? body}) => StreamedResponse(
body ?? Stream.value(utf8.encode('denied')),
401,
request: Request('GET', Uri.parse('https://api.example.com/me')),
headers: const {'www-authenticate': 'Bearer error="invalid_token"'},
reasonPhrase: 'Unauthorized',
persistentConnection: false,
);

/// A response that reports its final URL, as `IOClient` returns.
final class _ResponseWithUrl extends StreamedResponse
  implements BaseResponseWithUrl {
_ResponseWithUrl(this.url) : super(Stream.value(const []), 401);

@override
final Uri url;
}

void main() {
test('serves the whole rejected body from memory', () async {
  final rejection = await RejectedResponse.read(_rejected());

  expect(await rejection.toResponse().stream.bytesToString(), 'denied');
});

test('keeps the status, headers, reason and request', () async {
  final original = _rejected();

  final copy = (await RejectedResponse.read(original)).toResponse();

  expect(copy.statusCode, 401);
  expect(copy.headers, original.headers);
  expect(copy.reasonPhrase, 'Unauthorized');
  expect(copy.persistentConnection, isFalse);
  expect(copy.request, same(original.request));
  expect(copy.contentLength, 6);
});

test('keeps the url of a response that reports one', () async {
  final redirected = Uri.parse('https://api.example.com/v2/me');

  final copy = (await RejectedResponse.read(
    _ResponseWithUrl(redirected),
  )).toResponse();

  expect(
    copy,
    isA<BaseResponseWithUrl>().having(
      (response) => response.url,
      'url',
      redirected,
    ),
  );
});

test('every response gets its own body stream', () async {
  final rejection = await RejectedResponse.read(_rejected());

  await rejection.toResponse().stream.drain<void>();

  expect(await rejection.toResponse().stream.bytesToString(), 'denied');
});

test('a body that fails to arrive fails the read', () {
  final broken = _rejected(
    body: Stream.error(ClientException('connection reset')),
  );

  expect(RejectedResponse.read(broken), throwsA(isA<ClientException>()));
});

test('matches only a rejected response', () async {
  final rejection = await RejectedResponse.read(_rejected());

  expect(RejectedResponse.matches(rejection), isTrue);
  expect(RejectedResponse.matches(const FormatException()), isFalse);
});
}
```

- [ ] **Step 2: Write the failing replay tests**

Create `packages/token_manager_http/test/http_token_client_replay_test.dart`:

```dart
import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/client_fixture.dart';
import 'helpers/fake_answer.dart';
import 'helpers/sent_request.dart';

FakeAnswer _forbidOld(SentRequest request) =>
  request.authorization == 'Bearer old'
  ? const FakeAnswer(403, 'forbidden')
  : FakeAnswer.ok;

void main() {
group('a rejected Request', () {
  test('is replayed once with refreshed tokens', () async {
    final fixture = ClientFixture();

    final response = await fixture.client.get(ClientFixture.url);

    expect(response.statusCode, 200);
    expect(fixture.inner.requests, hasLength(2));
    expect(fixture.inner.requests[1].authorization, 'Bearer fresh-1');
    expect(fixture.refresher.calls, 1);
  });

  test('is replayed with its method, headers and body', () async {
    final fixture = ClientFixture();

    await fixture.client.send(fixture.post());

    final replay = fixture.inner.requests[1];
    expect(replay.request.method, 'POST');
    expect(replay.request.headers['x-trace'], '1');
    expect(replay.text, '{"name":"ada"}');
  });

  test('has its body read before the replay is sent', () async {
    final fixture = ClientFixture();

    await fixture.client.get(ClientFixture.url);

    expect(fixture.inner.requests[1].unreadBodies, 0);
  });

  test('is returned with its body when the replay is rejected too', () async {
    final fixture = ClientFixture(answer: (_) => FakeAnswer.unauthorized);

    final response = await fixture.client.get(ClientFixture.url);

    expect(response.statusCode, 401);
    expect(response.body, 'denied');
    expect(fixture.inner.requests, hasLength(2));
  });

  test('is returned unreplayed when the manager cannot refresh', () async {
    final fixture = ClientFixture(hasRefresher: false);

    final response = await fixture.client.get(ClientFixture.url);

    expect(response.statusCode, 401);
    expect(response.body, 'denied');
    expect(fixture.inner.requests, hasLength(1));
  });
});

group('single flight', () {
  test('concurrent rejected requests share one refresh', () async {
    final fixture = ClientFixture();

    final responses = await Future.wait([
      fixture.client.get(ClientFixture.url),
      fixture.client.get(ClientFixture.url),
      fixture.client.get(ClientFixture.url),
    ]);

    expect(responses.map((response) => response.statusCode), [200, 200, 200]);
    expect(fixture.refresher.calls, 1);
    // Three first attempts plus one replay per rejected request.
    expect(fixture.inner.requests, hasLength(6));
  });

  test(
    'tokens replaced since the rejection are used without a refresh',
    () async {
      // late: the answer callback needs the fixture it is passed to.
      late final ClientFixture fixture;
      fixture = ClientFixture(
        answer: (sent) async {
          if (sent.authorization != 'Bearer old') {
            return FakeAnswer.ok;
          }
          await fixture.manager.setTokens(
            const TokenSet(accessToken: 'new'),
          );
          return FakeAnswer.unauthorized;
        },
      );

      final response = await fixture.client.get(ClientFixture.url);

      expect(response.statusCode, 200);
      expect(fixture.refresher.calls, 0);
      expect(fixture.inner.requests[1].authorization, 'Bearer new');
    },
  );
});

group('failures', () {
  test('a terminal refresh failure is thrown and ends the session', () async {
    final fixture = ClientFixture(refreshFailure: const InvalidGrant());

    await expectLater(
      fixture.client.get(ClientFixture.url),
      throwsA(isA<InvalidGrant>()),
    );
    expect(await fixture.manager.current(), isNull);
    expect(fixture.inner.requests, hasLength(1));
  });

  test(
    'a transient refresh failure is thrown and keeps the session',
    () async {
      final fixture = ClientFixture(
        refreshFailure: const Transient('offline'),
      );

      await expectLater(
        fixture.client.get(ClientFixture.url),
        throwsA(isA<Transient>()),
      );
      expect(await fixture.manager.current(), same(ClientFixture.old));
    },
  );

  test('a 401 whose body fails to arrive fails the call unreplayed', () async {
    final fixture = ClientFixture(
      answer: (_) => FakeAnswer(401, '', ClientException('connection reset')),
    );

    await expectLater(
      fixture.client.get(ClientFixture.url),
      throwsA(isA<ClientException>()),
    );
    expect(fixture.inner.requests, hasLength(1));
    expect(fixture.refresher.calls, 0);
  });

  test('a network error during the replay reaches the caller', () async {
    final fixture = ClientFixture(
      answer: (sent) => sent.authorization == 'Bearer old'
          ? FakeAnswer.unauthorized
          : throw ClientException('offline'),
    );

    await expectLater(
      fixture.client.get(ClientFixture.url),
      throwsA(
        isA<ClientException>().having(
          (error) => error.message,
          'message',
          'offline',
        ),
      ),
    );
  });
});

group('isAuthFailure', () {
  test('decides which responses are replayed', () async {
    final fixture = ClientFixture(answer: _forbidOld);
    final client = fixture.clientWith(
      isAuthFailure: (response) => response.statusCode == 403,
    );

    final response = await client.get(ClientFixture.url);

    expect(response.statusCode, 200);
    expect(fixture.inner.requests, hasLength(2));
  });

  test('a 403 is not replayed by default', () async {
    final fixture = ClientFixture(answer: _forbidOld);

    final response = await fixture.client.get(ClientFixture.url);

    expect(response.statusCode, 403);
    expect(fixture.refresher.calls, 0);
  });
});
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/token_manager_http && dart test test/rejected_response_test.dart test/http_token_client_replay_test.dart`
Expected: `rejected_response_test.dart` fails to compile (`Target of URI doesn't exist`). In the replay file, the tests that expect a replay fail with `Expected: <200> Actual: <401>`.

- [ ] **Step 4: Implement RejectedResponse**

Create `packages/token_manager_http/lib/src/rejected_response.dart`:

```dart
import 'dart:typed_data';

import 'package:http/http.dart';

/// A response that failed authorization, read to the end so its connection
/// is released before the request is sent again.
///
/// `HttpTokenClient` throws it inside `TokenManager.authorize`, which replays
/// the request on it, and turns it back into a response with [toResponse]
/// when no replay follows. It never reaches the caller.
final class RejectedResponse implements Exception {
const RejectedResponse._(this._response, this._body);

final StreamedResponse _response;
final Uint8List _body;

/// Reads the body of [response] to the end.
///
/// Throws what the body stream fails with, such as a [ClientException].
static Future<RejectedResponse> read(StreamedResponse response) async {
  final body = await response.stream.toBytes();
  return RejectedResponse._(response, body);
}

/// Whether [error] is a [RejectedResponse].
static bool matches(Object error) => error is RejectedResponse;

/// A response like the rejected one whose body is served from memory.
StreamedResponse toResponse() => switch (_response) {
  BaseResponseWithUrl(:final url) => _BufferedResponseWithUrl(
    _response,
    _body,
    url,
  ),
  _ => _BufferedResponse(_response, _body),
};

@override
String toString() => 'RejectedResponse: HTTP ${_response.statusCode}';
}

/// A copy of a rejected [StreamedResponse] whose body comes from memory.
final class _BufferedResponse extends StreamedResponse {
_BufferedResponse(StreamedResponse rejected, Uint8List body)
  : super(
      ByteStream.fromBytes(body),
      rejected.statusCode,
      contentLength: body.length,
      request: rejected.request,
      headers: rejected.headers,
      isRedirect: rejected.isRedirect,
      persistentConnection: rejected.persistentConnection,
      reasonPhrase: rejected.reasonPhrase,
    );
}

/// A [_BufferedResponse] that keeps the final [url] of the rejected response.
final class _BufferedResponseWithUrl extends _BufferedResponse
  implements BaseResponseWithUrl {
_BufferedResponseWithUrl(super.rejected, super.body, this.url);

@override
final Uri url;
}
```

- [ ] **Step 5: Route replayable requests through authorize**

Replace `packages/token_manager_http/lib/src/http_token_client.dart` with:

```dart
import 'dart:async';

import 'package:http/http.dart';
import 'package:token_manager/token_manager.dart';

import 'rejected_response.dart';
import 'request_copies.dart';

/// An `http` [Client] that sends requests with the tokens of a
/// [TokenManager] and replays a request once after the server rejects them.
///
/// The client never refreshes by itself: it asks the manager for valid
/// tokens before every request and reports the tokens a server rejected
/// through [TokenManager.authorize], so concurrent requests share one
/// refresh. Every attempt sends a copy, so the caller's request never gets
/// the token header.
///
/// Only a [Request] or an [AbortableRequest] is replayed, because its body is
/// in memory; the rejected body is read first so its connection is released.
/// A [StreamedRequest], a [MultipartRequest] and any other request are sent
/// once, and their rejection is returned as is.
///
/// ```dart
/// final client = HttpTokenClient<TokenSet>(manager: manager, inner: Client());
/// final response = await client.get(Uri.parse('https://api.example.com/me'));
/// ```
///
/// {@category getting-started}
final class HttpTokenClient<T> extends BaseClient {
/// Creates a client that sends through [inner] with the tokens of
/// [manager].
///
/// [headers] turns tokens into request headers; without it a `TokenSet` is
/// sent as `Authorization: Bearer <accessToken>`, and any other token type
/// throws an [ArgumentError]. [isAuthFailure] recognises a rejection, by
/// default status 401. A request for which [shouldAuthorize] returns
/// `false`, such as a login, is sent unchanged without tokens.
HttpTokenClient({
  required TokenManager<T> manager,
  required Client inner,
  Map<String, String> Function(T tokens)? headers,
  bool Function(BaseResponse response)? isAuthFailure,
  bool Function(BaseRequest request)? shouldAuthorize,
}) : _manager = manager,
     _inner = inner,
     _headers = headers ?? _bearer,
     _isAuthFailure = isAuthFailure ?? _isUnauthorized,
     _shouldAuthorize = shouldAuthorize ?? _authorizesAll {
  if (headers == null && T != TokenSet) {
    throw ArgumentError.value(
      headers,
      'headers',
      'is required unless the token type is TokenSet',
    );
  }
}

/// The status that rejects the tokens unless [isAuthFailure] says
/// otherwise.
static const int _unauthorized = 401;

static const RequestCopies _copies = RequestCopies();

final TokenManager<T> _manager;
final Client _inner;
final Map<String, String> Function(T tokens) _headers;
final bool Function(BaseResponse response) _isAuthFailure;
final bool Function(BaseRequest request) _shouldAuthorize;

/// Sends [request] with valid tokens, replaying a rejected [Request] once.
///
/// Throws `NotAuthenticated`, `InvalidGrant` or `Transient` when the
/// manager has no tokens to send.
@override
Future<StreamedResponse> send(BaseRequest request) async {
  if (!_shouldAuthorize(request)) {
    return _inner.send(request);
  }
  return switch (_copies.asReplayable(request)) {
    final Request replayable => _sendReplayable(replayable),
    null => _sendOnce(request),
  };
}

/// Sends [request] through [TokenManager.authorize], which replays it once
/// after a rejection; a rejection that is not replayed is returned.
Future<StreamedResponse> _sendReplayable(Request request) async {
  try {
    return await _manager.authorize<StreamedResponse>(
      (tokens) => _attempt(request, tokens),
      isAuthFailure: RejectedResponse.matches,
    );
  } on RejectedResponse catch (rejection) {
    return rejection.toResponse();
  }
}

/// Sends a copy of [request] with [tokens]; a rejected response is read to
/// the end and thrown as a [RejectedResponse].
Future<StreamedResponse> _attempt(Request request, T tokens) async {
  final response = await _inner.send(
    _copies.copyOf(request, _headers(tokens)),
  );
  if (!_isAuthFailure(response)) {
    return response;
  }
  throw await RejectedResponse.read(response);
}

/// Sends [request] a single time; a rejection is returned as is and its
/// tokens are reported, so the next request gets new ones.
Future<StreamedResponse> _sendOnce(BaseRequest request) async {
  final tokens = await _manager.validToken();
  final response = await _inner.send(
    _copies.streamOf(request, _headers(tokens)),
  );
  if (_isAuthFailure(response)) {
    unawaited(_reportRejected(tokens));
  }
  return response;
}

/// Asks the manager to renew [rejected] and ignores the outcome, because
/// the caller already has the rejected response.
Future<void> _reportRejected(T rejected) async {
  try {
    await _manager.validToken(rejected: rejected);
  } on Exception {
    // The caller already has the rejected response; a terminal failure
    // still ends the session inside the manager.
  }
}

static Map<String, String> _bearer(Object? tokens) => switch (tokens) {
  TokenSet(:final accessToken) => {'Authorization': 'Bearer $accessToken'},
  _ => throw StateError('HttpTokenClient needs headers for this token type.'),
};

static bool _isUnauthorized(BaseResponse response) =>
    response.statusCode == _unauthorized;

static bool _authorizesAll(BaseRequest request) => true;
}
```

Append to `packages/token_manager_http/CHANGELOG.md`:

```markdown
- A `Request` or `AbortableRequest` that the server rejects is sent once more
with the tokens `TokenManager.authorize` provides; concurrent rejections
share one refresh. The rejected body is read first so its connection is
released, and a rejection that is not replayed is returned with its body.
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/token_manager_http && dart test`
Expected: PASS (all tests; `http_token_client_test.dart` still passes, because its `Request` tests answer 200 and its send-once tests use streamed and multipart requests).

- [ ] **Step 7: Format and analyze**

Run: `dart format packages && dart format packages && dart analyze packages`
Expected: `0 changed` on the second run; `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add packages/token_manager_http
git commit -m "feat(token_manager_http): replay a rejected request once after reading its body

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: close() closes the inner client once and leaves the manager open

**Files:**
- Modify: `packages/token_manager_http/lib/src/http_token_client.dart`
- Modify: `packages/token_manager_http/CHANGELOG.md`
- Test: `packages/token_manager_http/test/http_token_client_close_test.dart`

**Interfaces:**
- Consumes: Task 4 `HttpTokenClient`; `ClientFixture`, `RecordingClient.closeCalls`.
- Produces: `void HttpTokenClient.close()` (idempotent; never disposes the manager); `send` after `close` throws `ClientException('HttpTokenClient is closed.', request.url)`.

- [ ] **Step 1: Write the failing tests**

Create `packages/token_manager_http/test/http_token_client_close_test.dart`:

```dart
import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/client_fixture.dart';

void main() {
test('close closes the inner client', () {
  final fixture = ClientFixture();

  fixture.client.close();

  expect(fixture.inner.closeCalls, 1);
});

test('closing twice closes the inner client once', () {
  final fixture = ClientFixture();

  fixture.client
    ..close()
    ..close();

  expect(fixture.inner.closeCalls, 1);
});

test('close does not dispose the manager', () async {
  final fixture = ClientFixture();

  fixture.client.close();

  await expectLater(
    fixture.manager.setTokens(const TokenSet(accessToken: 'next')),
    completes,
  );
  expect(await fixture.manager.validToken(), isA<TokenSet>());
});

test('a request after close fails without asking for tokens', () async {
  final fixture = ClientFixture(isSignedIn: false);

  fixture.client.close();

  await expectLater(
    fixture.client.get(ClientFixture.url),
    throwsA(isA<ClientException>()),
  );
  expect(fixture.inner.requests, isEmpty);
});
}
```

The last test runs signed out: if the client asked the manager first, it would fail with `NotAuthenticated` instead of `ClientException`. `setTokens` on a disposed manager throws (`Cannot add new events after calling close`), which is what the third test rules out.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/token_manager_http && dart test test/http_token_client_close_test.dart`
Expected: FAIL: `close closes the inner client` (`Expected: <1> Actual: <0>`, because `BaseClient.close` does nothing), `closing twice ...` (`Actual: <0>`), and `a request after close ...` (`NotAuthenticated` instead of `ClientException`).

- [ ] **Step 3: Implement close**

In `packages/token_manager_http/lib/src/http_token_client.dart`:

Below `static const int _unauthorized = 401;` add:

```dart
/// The message of the [ClientException] a request after [close] fails
/// with.
static const String _closedMessage = 'HttpTokenClient is closed.';
```

Below the field `final bool Function(BaseRequest request) _shouldAuthorize;` add:

```dart
bool _isClosed = false;
```

Replace the `send` method and its doc comment with:

```dart
/// Sends [request] with valid tokens, replaying a rejected [Request] once.
///
/// Throws `NotAuthenticated`, `InvalidGrant` or `Transient` when the
/// manager has no tokens to send, and a [ClientException] after [close].
@override
Future<StreamedResponse> send(BaseRequest request) async {
  if (_isClosed) {
    throw ClientException(_closedMessage, request.url);
  }
  if (!_shouldAuthorize(request)) {
    return _inner.send(request);
  }
  return switch (_copies.asReplayable(request)) {
    final Request replayable => _sendReplayable(replayable),
    null => _sendOnce(request),
  };
}

/// Closes the inner client once; the [TokenManager] stays open, because
/// this client does not own it.
@override
void close() {
  if (_isClosed) {
    return;
  }
  _isClosed = true;
  _inner.close();
}
```

In the class doc comment, add this paragraph before the ```` ```dart ```` example:

```dart
/// [close] closes the inner client but not the manager: dispose the manager
/// yourself when the session ends.
///
```

Append to `packages/token_manager_http/CHANGELOG.md`:

```markdown
- `close()` closes the inner client once and leaves the manager open; a
request after `close()` fails with a `ClientException`.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/token_manager_http && dart test`
Expected: PASS (all tests).

- [ ] **Step 5: Format and analyze**

Run: `dart format packages && dart format packages && dart analyze packages`
Expected: `0 changed` on the second run; `No issues found!`. `lib/src/http_token_client.dart` stays under 300 lines (about 190).

- [ ] **Step 6: Commit**

```bash
git add packages/token_manager_http
git commit -m "feat(token_manager_http): close the inner client once and leave the manager open

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: README, guides, dartdoc categories and a runnable example

**Files:**
- Create: `packages/token_manager_http/README.md`
- Create: `packages/token_manager_http/dartdoc_options.yaml`
- Create: `packages/token_manager_http/doc/getting_started.md`, `doc/replay.md`, `doc/testing.md`
- Create: `packages/token_manager_http/example/main.dart`

**Interfaces:**
- Consumes: the public API from Tasks 3 to 5 (`HttpTokenClient`, its five constructor parameters, `close()`), `package:http/testing.dart` `MockClient`.
- Produces: the published docs. `HttpTokenClient` and the library are in the `getting-started` category; `replay` and `testing` are guide-only categories (like gql's `clients`).

- [ ] **Step 1: Write the example**

Create `packages/token_manager_http/example/main.dart`:

```dart
import 'dart:io';

import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

final class _ExampleRefresher implements TokenRefresher<TokenSet> {
const _ExampleRefresher();

@override
Future<TokenSet> refresh(TokenSet current) async {
  // Call your token endpoint here. Throw InvalidGrant when the refresh
  // token was rejected for good, and Transient when a retry may succeed.
  return const TokenSet(accessToken: 'fresh');
}
}

Future<void> main() async {
final manager = TokenManager<TokenSet>.create(
  store: InMemoryTokenStore<TokenSet>(const TokenSet(accessToken: 'stale')),
  refresher: const _ExampleRefresher(),
);

// Stands in for the network: it answers 401 to every token but `fresh`.
// In an app the inner client is `Client()`.
final server = MockClient((request) async {
  if (request.headers['authorization'] != 'Bearer fresh') {
    return Response('expired', 401);
  }
  return Response('{"me":"ada"}', 200);
});

final client = HttpTokenClient<TokenSet>(manager: manager, inner: server);
final response = await client.get(Uri.parse('https://api.example.com/me'));
stdout.writeln(
  'Status ${response.statusCode} after one refresh and replay: '
  '${response.body}',
);

client.close();
await manager.dispose();
}
```

Run: `cd packages/token_manager_http && dart run example/main.dart`
Expected output: `Status 200 after one refresh and replay: {"me":"ada"}`

- [ ] **Step 2: Write the dartdoc options**

Create `packages/token_manager_http/dartdoc_options.yaml`:

```yaml
dartdoc:
categories:
  getting-started:
    markdown: doc/getting_started.md
    displayName: Getting Started
  replay:
    markdown: doc/replay.md
    displayName: Replay
  testing:
    markdown: doc/testing.md
    displayName: Testing
categoryOrder:
  - getting-started
  - replay
  - testing
showUndocumentedCategories: true
```

- [ ] **Step 3: Write the guides**

Create `packages/token_manager_http/doc/getting_started.md`:

````markdown
# Getting Started

`token_manager_http` provides `HttpTokenClient`, a `package:http`
`BaseClient` that attaches the tokens of a `TokenManager` to every request
and replays a request once after the server rejects them.

## Build the client

```dart
import 'package:http/http.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

HttpTokenClient<TokenSet> buildClient(TokenManager<TokenSet> manager) =>
  HttpTokenClient<TokenSet>(manager: manager, inner: Client());
```

`inner` is the client that really sends: `Client()`, an `IOClient`, a
`RetryClient`, or a `cupertino_http` / `cronet_http` client. For a
`TokenSet` the header is `Authorization: Bearer <accessToken>`. For your own
token type pass `headers`:

```dart
HttpTokenClient<MyTokens>(
manager: manager,
inner: Client(),
headers: (tokens) => {'Authorization': 'Bearer ${tokens.jwt}'},
);
```

Without `headers`, a token type other than `TokenSet` throws an
`ArgumentError`.

## What the client does

For every request the client asks the manager for valid tokens. The manager
refreshes them first when they are about to expire, and concurrent requests
share one refresh. A copy of the request is sent with the header, so your
request object never changes.

If the server rejects the tokens (status 401 by default), the client asks the
manager for a replacement and sends the request **once more**. It never
refreshes by itself and never loops: when the replay is rejected too, that
response is returned.

## Requests without tokens

A login runs before tokens exist. Exclude it with `shouldAuthorize`:

```dart
HttpTokenClient<TokenSet>(
manager: manager,
inner: Client(),
shouldAuthorize: (request) => request.url.path != '/oauth/token',
);
```

## Close it

`close()` closes the inner client, once. It does not dispose the manager,
which may serve other clients: call `manager.dispose()` yourself.

## Run the example

[`example/main.dart`](../example/main.dart) wires the client to a
`MockClient` that answers 401 to a stale token, and shows one refresh and one
replay without a network:

```console
$ dart run example/main.dart
Status 200 after one refresh and replay: {"me":"ada"}
```

## Where to go next

- **Replay**: which requests are replayed and what happens to the rejected
response.
- **Testing**: test code that uses the client without a network.
````

Create `packages/token_manager_http/doc/replay.md`:

````markdown
# Replay

A request is replayed only when it can be sent a second time with exactly
the same body.

| Request | Sent with tokens | Replayed after a rejection |
|---|---|---|
| `Request` (what `get`, `post`, `put`, `patch`, `delete` and `head` send) | yes, as a copy | once |
| `AbortableRequest` | yes, the abort trigger is kept | once |
| `StreamedRequest`, `AbortableStreamedRequest` | yes, the body is streamed through | no |
| `MultipartRequest`, `AbortableMultipartRequest` | yes | no |
| any other `BaseRequest`, including your own subclass of `Request` | yes | no |

A subclass of `Request` may build its body in `finalize`, so the client does
not copy it.

## The rejected response

- **Replayable request**: the rejected body is read to the end before the
replay is sent, so its connection is released. If no replay follows (the
manager has no replacement token, or the replay is rejected too) you get
the rejected response, with its body.
- **Request that is sent once**: the rejected response is returned untouched.
The client reports the rejected tokens to the manager without waiting, so
the next request gets new ones. Resend the request yourself if that is
safe.

If the body of a rejected response fails to arrive, the call fails with that
`ClientException` and nothing is replayed.

## One refresh for many requests

The client never refreshes. It asks `TokenManager.authorize` for a
replacement of the tokens the server rejected. When ten requests are rejected
at once, the manager runs one refresh and every request is replayed with its
result. When the tokens were already replaced (by another request or by
`setTokens`), the replay uses the new tokens without refreshing.

## Recognising a rejection

`isAuthFailure` decides which responses mean "these tokens were rejected". The
default is status 401. A server that answers 419 or 440 for an expired
session:

```dart
HttpTokenClient<TokenSet>(
manager: manager,
inner: Client(),
isAuthFailure: (response) => {401, 419, 440}.contains(response.statusCode),
);
```

Do not treat 403 as a rejection: it means the tokens are valid but not
allowed, and a refresh does not change that.

## Errors

| Thrown by `send`, `get`, ... | Meaning |
|---|---|
| `NotAuthenticated` | no session; the request was not sent |
| `InvalidGrant` | the refresh token is dead and the manager signed out |
| `Transient` | the refresh may succeed later; the session stays |
| `ClientException` | a network error, or a request after `close()` |

The manager's failures are not wrapped in a `ClientException`. Listen to
`manager.states` to send the user to sign-in on `Unauthenticated`.
````

Create `packages/token_manager_http/doc/testing.md`:

````markdown
# Testing

`HttpTokenClient` wraps any `Client`, so tests pass a `MockClient` from
`package:http/testing.dart` as `inner` and an `InMemoryTokenStore` to the
manager. Nothing touches the network.

```dart
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

final class _FixedRefresher implements TokenRefresher<TokenSet> {
int calls = 0;

@override
Future<TokenSet> refresh(TokenSet current) async {
  calls++;
  return const TokenSet(accessToken: 'fresh');
}
}

void main() {
test('a stale token is refreshed once and the request replayed', () async {
  final refresher = _FixedRefresher();
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(const TokenSet(accessToken: 'stale')),
    refresher: refresher,
  );
  final server = MockClient((request) async =>
      request.headers['authorization'] == 'Bearer fresh'
          ? Response('ok', 200)
          : Response('expired', 401));
  final client = HttpTokenClient<TokenSet>(manager: manager, inner: server);

  final response = await client.get(Uri.parse('https://api.example.com/me'));

  expect(response.statusCode, 200);
  expect(refresher.calls, 1);
});
}
```

Tips:

- **Read the header in lower case.** `request.headers` of `package:http` is
case-insensitive, so `headers['authorization']` finds `Authorization`.
- **Test the refresh failures.** Make the refresher throw `InvalidGrant` to
test the sign-out path, and `Transient` to test that the session stays.
- **Pump the event queue after an unreplayed rejection.** A rejected
`StreamedRequest` reports its tokens without waiting; call
`await pumpEventQueue()` before you check `manager.states` or the
refresher.
- **Close what you create.** `client.close()` closes the `MockClient`;
`manager.dispose()` closes the manager.
````

- [ ] **Step 4: Write the README**

Create `packages/token_manager_http/README.md`:

````markdown
# token_manager_http

[![Pub Version](https://img.shields.io/pub/v/token_manager_http.svg)](https://pub.dev/packages/token_manager_http)
![Dart](https://img.shields.io/badge/Dart-%3E%3D3.10-0175C2?logo=dart&logoColor=white)
![Transport](https://img.shields.io/badge/transport-package%3Ahttp-0175C2?logo=dart&logoColor=white)
![Part of](https://img.shields.io/badge/part_of-token__manager-informational)

**The `package:http` adapter for [`token_manager`](https://pub.dev/packages/token_manager)**: `HttpTokenClient`,
a `BaseClient` that wraps your `Client`, attaches the manager's tokens to every request and replays a request
once after the server rejects them. It depends only on `http` and `token_manager`.

## Contents

- [Install](#install)
- [Quick start](#quick-start)
- [What is replayed](#what-is-replayed)
- [Requests without tokens](#requests-without-tokens)
- [Headers and auth failures](#headers-and-auth-failures)
- [Errors](#errors)
- [Closing](#closing)
- [Testing](#testing)
- [Dependency constraints](#dependency-constraints)
- [Reference](#reference)

## Install

```yaml
dependencies:
http: ^1.5.0
token_manager: ^0.2.0
token_manager_http: ^0.1.0
```

## Quick start

```dart
import 'package:http/http.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

Future<String> fetchProfile(TokenManager<TokenSet> manager) async {
final client = HttpTokenClient<TokenSet>(manager: manager, inner: Client());
try {
  final response = await client.get(Uri.parse('https://api.example.com/me'));
  return response.body;
} finally {
  client.close();
}
}
```

The client never refreshes by itself: it asks the manager for valid tokens (which refreshes them first when
they are about to expire) and reports the tokens a server rejected. Concurrent requests share one refresh.
Every request is sent as a copy, so your request object never gets the token header. A runnable version
without a network is in [example/main.dart](example/main.dart).

**[doc/getting_started.md](doc/getting_started.md)**

## What is replayed

| Request | Replayed after a rejection |
|---|---|
| `Request`: everything `get`, `post`, `put`, `patch`, `delete`, `head` send | once |
| `AbortableRequest` | once, with its abort trigger |
| `StreamedRequest`, `MultipartRequest`, their abortable variants, other subclasses | no |

- **The rejected body is read first.** Before a replay the client reads the 401 to the end, so its connection
is released. A 401 that is not replayed still reaches you with its body.
- **A request that cannot be replayed** is sent once and its 401 is returned as is. The client reports the
rejected tokens, so the next request gets new ones.
- **One replay, never a loop.** When the replay is rejected too, that response is returned.

**[doc/replay.md](doc/replay.md)**

## Requests without tokens

A login or sign-up runs before tokens exist. Exclude it with `shouldAuthorize`, and it is sent unchanged
without asking the manager:

```dart
final client = HttpTokenClient<TokenSet>(
manager: manager,
inner: Client(),
shouldAuthorize: (request) => request.url.path != '/oauth/token',
);
```

Without it, a request sent while signed out fails with `NotAuthenticated`.

## Headers and auth failures

| Option | Default |
|---|---|
| `headers` | `Authorization: Bearer <accessToken>` for `TokenSet`; required for any other token type |
| `isAuthFailure` | status **401** |
| `shouldAuthorize` | every request |

```dart
final client = HttpTokenClient<MyTokens>(
manager: manager,
inner: Client(),
headers: (tokens) => {'X-Api-Key': tokens.apiKey},
isAuthFailure: (response) => {401, 419}.contains(response.statusCode),
);
```

The token header replaces a header with the same name on the request, in any letter case.

## Errors

| Thrown by `send`, `get`, ... | Meaning |
|---|---|
| `NotAuthenticated` | no session; the request was not sent |
| `InvalidGrant` | the session ended and the manager signed out |
| `Transient` | the refresh may succeed later; the session stays |
| `ClientException` | a network error, or a request after `close()` |

The manager's failures are not wrapped. Listen to `manager.states` to send the user to sign-in on
`Unauthenticated`.

## Closing

`close()` closes the inner client exactly once. It does **not** dispose the manager: the client does not own
it, and several clients may share one manager. Dispose the manager yourself when the session ends.

## Testing

Pass a `MockClient` from `package:http/testing.dart` as `inner` and an `InMemoryTokenStore` to the manager;
nothing touches the network. **[doc/testing.md](doc/testing.md)**

## Dependency constraints

`http ^1.5.0`: 1.5.0 added `AbortableRequest` and `AbortableStreamedRequest`, which the client uses to keep
the abort trigger of a request on the copy it sends.

## Reference

- [doc/getting_started.md](doc/getting_started.md) · [doc/replay.md](doc/replay.md) ·
[doc/testing.md](doc/testing.md)
- The core: [`token_manager`](https://pub.dev/packages/token_manager); siblings: `token_manager_dio`,
`token_manager_grpc` and `token_manager_gql`.
- Generate API docs: `cd packages/token_manager_http && dart doc .`
````

- [ ] **Step 5: Verify docs, example, analyzer and the publish dry run**

```bash
dart format packages && dart format packages
dart analyze packages
(cd packages/token_manager_http && dart test)
(cd packages/token_manager_http && dart run example/main.dart)
(cd packages/token_manager_http && dart doc --dry-run .)
(cd packages/token_manager_http && dart pub publish --dry-run)
```

Expected: `0 changed`; `No issues found!`; tests pass; the example prints `Status 200 after one refresh and replay: {"me":"ada"}`; `dart doc` reports no errors or broken links; the dry run ends with `Package has 0 warnings.`

- [ ] **Step 6: Commit**

```bash
git add packages/token_manager_http
git commit -m "docs(token_manager_http): add the README, guides, dartdoc categories and an example

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: CI, publishing, release notes and the root README

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/publish.yml`
- Modify: `docs/releasing.md`
- Modify: `README.md` (root)

**Interfaces:**
- Consumes: the finished package (Tasks 1 to 6).
- Produces: CI runs the package's tests on every matrix entry and its publish dry run on stable/ubuntu; a tag `token_manager_http-vX.Y.Z` publishes it.

- [ ] **Step 1: Add the CI steps**

In `.github/workflows/ci.yml`, insert after the `Test token_manager_gql` step:

```yaml
    - name: Test token_manager_http
      working-directory: packages/token_manager_http
      run: dart test
```

and insert after the `Publish dry run token_manager_gql` step (last step of the job):

```yaml
    - name: Publish dry run token_manager_http
      if: matrix.sdk == 'stable' && matrix.os == 'ubuntu-latest'
      working-directory: packages/token_manager_http
      run: dart pub publish --dry-run
```

Format and analyze already cover the package: they run on `packages`.

- [ ] **Step 2: Add the publish job and tag pattern**

In `.github/workflows/publish.yml`, add to `on.push.tags` after the gql pattern:

```yaml
    - 'token_manager_http-v[0-9]+.[0-9]+.[0-9]+*'
```

and append after the `publish-token_manager_gql` job:

```yaml

publish-token_manager_http:
  name: Publish token_manager_http
  if: startsWith(github.ref_name, 'token_manager_http-v')
  needs: verify
  permissions:
    id-token: write
  uses: dart-lang/setup-dart/.github/workflows/publish.yml@v1
  with:
    environment: pub.dev
    working-directory: packages/token_manager_http
```

The `verify` job needs no change: it derives the package from the tag (`${GITHUB_REF_NAME%%-v*}` gives `token_manager_http`).

- [ ] **Step 3: Update docs/releasing.md**

Replace the whole file with:

````markdown
# Releasing

Packages are published to pub.dev from GitHub Actions with OIDC automated
publishing. There are no secrets. The workflow is
`.github/workflows/publish.yml`; it runs when a tag `<package>-vX.Y.Z` is
pushed. CI also runs `dart pub publish --dry-run` for every package.

> **Status:** `token_manager`, `token_manager_dio` and `token_manager_grpc` 0.1.x
> are on pub.dev; 0.2.0 of these three, `token_manager_gql` 0.1.0 and
> `token_manager_http` 0.1.0 are the pending release. `token_manager_gql` and
> `token_manager_http` do not exist on pub.dev yet.

## One-time setup

For each package (`token_manager`, `token_manager_dio`, `token_manager_grpc`,
`token_manager_gql`, `token_manager_http`):

1. The package must already exist on pub.dev. Only a brand-new package
 (`token_manager_gql` and `token_manager_http` now) needs a manual first
 publish: once the core version it depends on is live, run
 `dart pub publish` from `packages/<package>`. The other packages are
 already on pub.dev.
2. On pub.dev open the package, then Admin, then Automated publishing, and
 enable GitHub Actions publishing:
 - Repository: `4akloon/dart_token_manager`
 - Tag pattern: `<package>-v{{version}}`, for example
   `token_manager_http-v{{version}}`
 - Require GitHub Actions environment: `pub.dev`

In the GitHub repository, create the environment `pub.dev` (Settings, then
Environments) and add a required reviewer. Every publish then waits for an
approval.

## Release steps

1. Bump `version` in the package `pubspec.yaml` and add a `CHANGELOG.md` entry.
 Before 1.0 a breaking change is a minor bump; only the changed package is
 bumped.
2. Merge the change to `main`.
3. Tag the merge commit and push the tag:

 ```bash
 git tag <package>-vX.Y.Z
 git push origin <package>-vX.Y.Z
 ```

4. The `verify` job fails the run if the tag version differs from the pubspec
 version. Otherwise approve the `pub.dev` environment to publish.

## Order

Release **`token_manager`** (the core) first. The adapters
(`token_manager_dio`, `token_manager_grpc`, `token_manager_gql`,
`token_manager_http`) depend on it with a `^0.2.0` style constraint that
resolves from pub.dev, so a new adapter release that needs a new core version
can only be published after the core is live. The adapters do not depend on
each other and can follow in any order.
````

- [ ] **Step 4: Update the root README**

In the root `README.md` make these replacements:

1. Badge: `transports-dio%20%7C%20gRPC%20%7C%20GraphQL` becomes `transports-dio%20%7C%20http%20%7C%20gRPC%20%7C%20GraphQL`.
2. Tagline: `state, and thin transport adapters for dio, gRPC and GraphQL.**` becomes `state, and thin transport adapters for dio, http, gRPC and GraphQL.**`
3. Status note: replace
 ```
 > 0.1.x are on pub.dev; 0.2.0 of these three and the first release of `token_manager_gql` (0.1.0)
 > are not published yet. Until then use a path or git dependency for the new versions.
 ```
 with
 ```
 > 0.1.x are on pub.dev; 0.2.0 of these three and the first releases of `token_manager_gql` and
 > `token_manager_http` (0.1.0) are not published yet. Until then use a path or git dependency for
 > the new versions.
 ```
4. Packages table: replace the row
 ```
 | `token_manager_http` | **Planned** — `HttpTokenClient` for [`package:http`](https://pub.dev/packages/http). |
 ```
 with
 ```
 | [`token_manager_http`](packages/token_manager_http) | **package:http** adapter (`^0.1.0`) — `HttpTokenClient`, a `BaseClient` over any [`http`](https://pub.dev/packages/http) `Client`. |
 ```
5. Install comment: `# or token_manager_grpc: ^0.2.0 / token_manager_gql: ^0.1.0` becomes `# or token_manager_http: ^0.1.0 / token_manager_grpc: ^0.2.0 / token_manager_gql: ^0.1.0`.
6. After the dio code block, replace
 ```
 gRPC and GraphQL follow the same shape — see
 [`token_manager_grpc`](packages/token_manager_grpc/README.md) and
 [`token_manager_gql`](packages/token_manager_gql/README.md).
 ```
 with
 ```
 `package:http`, gRPC and GraphQL follow the same shape — see
 [`token_manager_http`](packages/token_manager_http/README.md),
 [`token_manager_grpc`](packages/token_manager_grpc/README.md) and
 [`token_manager_gql`](packages/token_manager_gql/README.md).
 ```
7. Documentation list: `- [dio](packages/token_manager_dio/README.md) · [gRPC](packages/token_manager_grpc/README.md) · [GraphQL](packages/token_manager_gql/README.md) — adapter guides.` becomes `- [dio](packages/token_manager_dio/README.md) · [http](packages/token_manager_http/README.md) · [gRPC](packages/token_manager_grpc/README.md) · [GraphQL](packages/token_manager_gql/README.md) — adapter guides.`

- [ ] **Step 5: Verify**

```bash
dart pub get
dart format packages && dart format packages
dart analyze packages
for p in token_manager token_manager_dio token_manager_grpc token_manager_gql token_manager_http; do (cd packages/$p && dart test) || exit 1; done
(cd packages/token_manager_http && dart pub publish --dry-run)
grep -n 'token_manager_http' .github/workflows/ci.yml .github/workflows/publish.yml docs/releasing.md README.md
```

Expected: `0 changed`; `No issues found!`; all five packages pass; `Package has 0 warnings.`; the grep shows the test step, the dry-run step, the tag pattern, the job, the releasing references and the README row and links.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/ci.yml .github/workflows/publish.yml docs/releasing.md README.md
git commit -m "build: test, dry-run and publish token_manager_http

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Open questions (not blocking the tasks)

1. **CLAUDE.md "Where things are"** lists only the dio and gRPC adapters. It is left unchanged here; add `token_manager_gql` and `token_manager_http` in a separate `docs:` commit if wanted.
2. **Spec wording.** Section 6 says unreplayable bodies "return the error without replay". In `package:http` a 401 is a response, not an error, so the plan returns the response. Update the spec sentence when this lands.
3. **`HttpTokenClient` member count** is about 17 (5 options, 2 constants, the copies helper, the closed flag, 2 public methods, 4 private methods, 3 static defaults), a little over the soft "about 15". If a reviewer objects, move `_bearer`, `_isUnauthorized` and `_authorizesAll` into a private `_Defaults` class in the same file.
