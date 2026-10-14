# token_manager core redesign: implementation plan 1 (phases 0-2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lay the tooling foundation, build the dependency-free layered core of `token_manager` (single-flight refresh, typed failures, observable state, stream relay, registry), and keep the old API alive as a deprecated facade over it.

**Architecture:** An internal `TokenEngine<T>` owns all state and concurrency (lazy load, one shared in-flight refresh, compare-and-skip on the rejected token, serialised store writes). The public `TokenManager<T>` keeps its name and is evolved in place: new members (`validToken`, `states`, `authorize`, ...) sit next to the old members, which become `@Deprecated` and delegate to the engine. Transport adapters (plan 2) and storage packages (plan 3) are out of scope here.

**Tech Stack:** Dart 3.10+ pub workspace, `package:test`, `package:lints`, GitHub Actions. No runtime dependencies in the core (`rxdart` is removed).

**Spec:** `docs/superpowers/specs/2026-10-14-token-manager-redesign-design.md` (sections 3-8 and roadmap phases 0-2). Plans for phase 3 (adapters), phase 4 (storage) and phase 5 (release) are written after this plan lands, against the real core signatures.

## Global Constraints

- Work on branch `refactor/layered-core` created from `main`; never commit to `main`.
- Every commit message uses Conventional Commits with a package scope (`feat(token_manager): ...`, `build: ...`, `docs: ...`) and ends with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Minimum SDK `>=3.10.0` (packages `^3.10.0`); every package pubspec has `resolution: workspace`; no tracked `pubspec_overrides.yaml`.
- The `token_manager` core has no runtime dependencies besides the Dart SDK (`rxdart` removed); the token type stays generic (`T`).
- Never consume a stream with `await for`; stream lifecycle (pause, resume, cancel) must reach the source.
- Code rules: object-oriented, no top-level functions except `main` (in tests and `example/`); no `!`, no `dynamic`; every `catch` has an `on` clause and `Error` is never caught; booleans are named positively; `///` docs with a one-sentence summary and `[brackets]`; `late` needs a comment.
- Never add `// ignore:` without a reason comment; never remove a lint to make code pass.
- Size limits: lib file 300 lines, test file 500, method 40, parameters 5, nesting 3, about 15 members per class, one public class or sealed family per file, no `utils`/`helpers`/`common` files in `lib/`, no `part`.
- `dart analyze packages` must print `No issues found!` and `dart format --output=none --set-exit-if-changed packages` must exit 0 at the end of every task.
- Tests ship in the same commit as the code; no network in tests; one behaviour per test.
- All code, comments and docs are in English.

## Review Focus

The spec implies these inputs but no happy-path test would exercise them; each has a pinning test in the task named in brackets.

1. A refresh returns a token already inside the skew window: the caller must get it back, with no second refresh and no hang. [Task 8]
2. The store throws while persisting a freshly refreshed token: the caller sees the error, the in-memory session stays on the old token, and the next call retries instead of wedging. [Task 8]
3. The refresher throws something that is not a `RefreshFailure` (for example a `FormatException`): treat it as transient; never log the user out. [Task 8]
4. A stream listener cancels before the token arrives: the source stream is never opened, and a pause requested before the source exists is applied once it opens. [Task 10]
5. A legacy `TokenManagerRefreshDelegate` throws `RevokedTokensException`, or no delegate was given at all: the first logs out, the second never attempts a refresh. [Task 11]

## File structure

Created in `packages/token_manager/`:

| Path | Responsibility |
|---|---|
| `lib/src/clock.dart` | `Clock`: injectable time source |
| `lib/src/refresh_failure.dart` | sealed `RefreshFailure`: `InvalidGrant`, `Transient` |
| `lib/src/not_authenticated.dart` | `NotAuthenticated`: no tokens available |
| `lib/src/token_store.dart` | `TokenStore<T>` interface (read, write, delete) |
| `lib/src/in_memory_token_store.dart` | `InMemoryTokenStore<T>` |
| `lib/src/token_refresher.dart` | `TokenRefresher<T>` interface |
| `lib/src/token_info.dart` | `TokenInfo<T>` interface (`expiresAt`) |
| `lib/src/auth_state.dart` | sealed `AuthState<T>`: `Unauthenticated`, `Authenticated`, `Refreshing` |
| `lib/src/token_set.dart`, `lib/src/token_set_info.dart` | ready-made token value and its `TokenInfo` |
| `lib/src/engine/replay_value.dart` | holder whose stream replays the last value |
| `lib/src/engine/token_engine.dart` | all state and concurrency |
| `lib/src/engine/authorized_call.dart` | send with a token, replay once after an auth failure |
| `lib/src/engine/relay_stream.dart` | stream relay with a faithful lifecycle |
| `lib/src/legacy/storage_token_store.dart` | adapts old `TokenStorage<T>` to `TokenStore<T>` |
| `lib/src/legacy/delegate_token_refresher.dart` | adapts old refresh delegate to `TokenRefresher<T>` |
| `lib/src/revoked_tokens_exception.dart` | `RevokedTokensException` (moved out of `token_manager.dart`) |
| `lib/src/token_manager_registry.dart` | provider id to `TokenManager<T>` |

Modified: `lib/token_manager.dart`, `lib/src/token_manager.dart` (rewritten), `lib/src/token_storage.dart`, `lib/src/token_manager_refresh_delegate.dart`, `lib/src/token_info_delegate.dart`, `pubspec.yaml`, `example/main.dart`, `README.md`, `CHANGELOG.md`. Deleted: the old internal `lib/src/token_store.dart` content (renamed in Task 6, removed in Task 11).

Test layout mirrors `lib/src/`: `test/helpers/` (fakes, `EngineFixture`, `size_limits.dart`), `test/quality/`, `test/engine/`, `test/legacy/`.

---

### Task 1: Branch, workspace resolution and SDK floor

**Files:**
- Modify: `pubspec.yaml`, `packages/token_manager/pubspec.yaml`, `packages/token_manager_dio/pubspec.yaml`, `packages/token_manager_grpc/pubspec.yaml`
- Delete: `packages/token_manager/pubspec_overrides.yaml`, `packages/token_manager_dio/pubspec_overrides.yaml`, `packages/token_manager_grpc/pubspec_overrides.yaml`

**Interfaces:**
- Consumes: nothing.
- Produces: a working pub workspace (`dart pub get` at the root resolves all three packages) and the branch every later task commits to.

- [ ] **Step 1: Create the branch and commit the design documents**

```bash
cd /home/genius/projects/dart_token_manager
git switch -c refactor/layered-core
git add docs
git commit -m "docs: add the redesign spec and implementation plan 1

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2: Replace the root `pubspec.yaml` with**

```yaml
name: root
publish_to: none

environment:
  sdk: ">=3.10.0 <4.0.0"

dev_dependencies:
  lints: ^6.1.0

workspace:
  - packages/token_manager
  - packages/token_manager_dio
  - packages/token_manager_grpc
```

- [ ] **Step 3: Raise the SDK floor and add `resolution: workspace` in each package pubspec**

```bash
python3 - <<'EOF'
for package in ['token_manager', 'token_manager_dio', 'token_manager_grpc']:
    path = f'packages/{package}/pubspec.yaml'
    text = open(path).read()
    text = text.replace('sdk: ^3.7.0', 'sdk: ^3.10.0')
    text = text.replace('sdk: ^3.10.0\n', 'sdk: ^3.10.0\n\nresolution: workspace\n', 1)
    open(path, 'w').write(text)
EOF
git rm packages/token_manager/pubspec_overrides.yaml packages/token_manager_dio/pubspec_overrides.yaml packages/token_manager_grpc/pubspec_overrides.yaml
```

Each package pubspec must now contain, in this order: the `environment:` block with `sdk: ^3.10.0`, a blank line, `resolution: workspace`, a blank line, then `dependencies:`.

- [ ] **Step 4: Resolve the workspace**

Run: `dart pub get`
Expected: ends with `Got dependencies!` and no resolution error (the `token_manager: ^0.1.0` constraints in `_dio` and `_grpc` are satisfied by the workspace member at version 0.1.0).

- [ ] **Step 5: Confirm the packages still compile**

Run: `dart analyze packages 2>&1 | tail -n 5`
Expected: no `error` lines (style findings are fixed in Task 2).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml packages
git commit -m "build: resolve the packages through the pub workspace

Move resolution: workspace into each pubspec.yaml, drop the tracked
pubspec_overrides.yaml files and raise the SDK floor to 3.10.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Merge the typed_openapi lint set

**Files:**
- Modify: `analysis_options.yaml`, plus whatever source files the new rules flag in the three packages (behaviour-preserving edits only).

**Interfaces:**
- Consumes: Task 1 (workspace resolves).
- Produces: the zero-findings analyze gate every later task relies on.

- [ ] **Step 1: Replace `analysis_options.yaml` with**

```yaml
# Every rule here passes with zero findings, so `dart analyze packages` must
# print "No issues found!". Enable a new lint only when it is stable, available
# in the minimum SDK and has zero findings. The rule set is ported from
# typed_openapi; the Flutter widget lints it never had are not included.
include: package:lints/recommended.yaml

linter:
  rules:
    # Types and signatures
    - always_declare_return_types
    - always_put_required_named_parameters_first
    - avoid_annotating_with_dynamic
    - avoid_dynamic_calls
    - avoid_final_parameters
    - avoid_types_as_parameter_names
    - avoid_types_on_closure_parameters
    - avoid_unused_constructor_parameters
    - matching_super_parameters
    - parameter_assignments
    - tighten_type_of_initializing_formals
    - type_annotate_public_apis

    # Immutability and class design
    - avoid_classes_with_only_static_members
    - avoid_field_initializers_in_const_classes
    - avoid_implementing_value_types
    - avoid_returning_this
    - avoid_setters_without_getters
    - prefer_asserts_in_initializer_lists
    - prefer_asserts_with_message
    - prefer_const_constructors
    - prefer_const_constructors_in_immutables
    - prefer_const_declarations
    - prefer_const_literals_to_create_immutables
    - prefer_final_in_for_each
    - prefer_final_locals
    - prefer_mixin
    - sort_constructors_first
    - sort_unnamed_constructors_first
    - test_types_in_equals
    - use_enums
    - use_setters_to_change_properties
    - use_to_and_as_if_applicable

    # Control flow and expressions
    - avoid_bool_literals_in_conditional_expressions
    - avoid_multiple_declarations_per_line
    - join_return_with_assignment
    - literal_only_boolean_expressions
    - no_literal_bool_comparisons
    - no_self_assignments
    - noop_primitive_operations
    - prefer_if_elements_to_conditional_expressions
    - prefer_int_literals
    - prefer_null_aware_method_calls
    - switch_on_type
    - unnecessary_await_in_return
    - unnecessary_breaks
    - unnecessary_lambdas
    - unnecessary_null_aware_operator_on_extension_on_nullable
    - unnecessary_statements
    - use_is_even_rather_than_modulo
    - use_named_constants
    - use_string_buffers
    - use_truncating_division

    # Errors, async and resources
    - avoid_catches_without_on_clauses
    - avoid_catching_errors
    - avoid_print
    - avoid_slow_async_io
    - avoid_void_async
    - cancel_subscriptions
    - close_sinks
    - only_throw_errors
    - throw_in_finally

    # Web compatibility (dio, http and gql run on Flutter web)
    - avoid_double_and_int_checks
    - avoid_js_rounded_ints
    - avoid_type_to_string
    - no_runtimetype_tostring

    # Strings, imports and files
    - combinators_ordering
    - conditional_uri_does_not_exist
    - directives_ordering
    - eol_at_end_of_file
    - file_names
    - leading_newlines_in_multiline_strings
    - library_names
    - prefer_relative_imports
    - prefer_single_quotes
    - require_trailing_commas
    - unnecessary_library_directive
    - unnecessary_raw_strings
    - unreachable_from_main
    - use_raw_strings

    # Docs, tests and pubspec
    - deprecated_consistency
    - deprecated_member_use_from_same_package
    - missing_code_block_language_in_doc_comment
    - public_member_api_docs
    - sort_pub_dependencies
    - unnecessary_ignore
    - use_test_throws_matchers

formatter:
  trailing_commas: preserve
```

- [ ] **Step 2: Measure the findings**

Run: `dart analyze packages 2>&1 | tail -n 40`
Expected: a list of findings (docs, trailing commas, sorted dependencies, and similar). Record the count. If it is above 60 after Step 3, stop and report instead of continuing.

- [ ] **Step 3: Apply the mechanical fixes**

```bash
dart fix --apply packages
dart format packages
dart analyze packages 2>&1 | tail -n 40
```

- [ ] **Step 4: Fix what is left by hand, without changing behaviour**

Typical remaining cases and the fix for each:
- `sort_pub_dependencies`: sort the keys under `dependencies:` and `dev_dependencies:` alphabetically and remove blank lines between them (`packages/token_manager_dio/pubspec.yaml`: `dio`, `token_manager`; `packages/token_manager_grpc/pubspec.yaml`: `async`, `grpc`, `token_manager`).
- `public_member_api_docs`: add a one-sentence `///` summary.
- `avoid_types_on_closure_parameters`: remove the type from the closure parameter.
- `avoid_catches_without_on_clauses`: add `on Exception`; if the code deliberately catches everything, stop and report instead of choosing.
- Never add `// ignore:` to silence a finding.

- [ ] **Step 5: Verify the gate**

Run: `dart analyze packages && dart format --output=none --set-exit-if-changed packages`
Expected: `No issues found!` and exit code 0.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: adopt the typed_openapi lint set

Merge the explicit rule set into analysis_options.yaml and fix the
findings without changing behaviour.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: CLAUDE.md and CONTRIBUTING.md

**Files:**
- Create: `CLAUDE.md`, `CONTRIBUTING.md`

**Interfaces:**
- Consumes: Task 2 (the rules described must already be enforced).
- Produces: the written rules later tasks and agents follow.

- [ ] **Step 1: Create `CLAUDE.md`**

````markdown
# dart_token_manager

A Dart pub workspace for the client-side lifecycle of authentication tokens:
storage, single-flight refresh, and transport integrations (dio, http, gRPC,
GraphQL). The design is in
`docs/superpowers/specs/2026-10-14-token-manager-redesign-design.md`; the
implementation plans are in `docs/superpowers/plans/`.

## Commands

Run from the repository root unless a command says otherwise.

```bash
dart pub get
dart format packages                   # a second run must change 0 files
dart analyze packages                  # must print "No issues found!"
cd packages/<package> && dart test     # run a package's tests
dart pub publish --dry-run             # inside a publishable package
```

## Where things are

- `packages/token_manager`: the core, pure Dart, no runtime dependencies.
  `lib/token_manager.dart` is the only public barrel; everything else is under
  `lib/src/`. The state and concurrency live in `lib/src/engine/token_engine.dart`.
- `packages/token_manager_dio`, `packages/token_manager_grpc`: transport
  adapters. They depend only on the core and their transport.
- `test/` mirrors `lib/src/`; shared fakes are in `test/helpers/`; the size
  limits are enforced by `test/quality/size_limits_test.dart`.

## Code rules

- Object-oriented code. No top-level functions, except `main` in `example/`
  and in tests. Helpers are private methods; constants live in their class.
- Use Dart 3.10 features: dot shorthands, null-aware elements, switch
  expressions and patterns, records, class modifiers.
- No `!` and no `dynamic`. `late` needs a comment saying why.
- `catch` always has an `on` clause. `Error` is never caught.
- Name booleans positively; no positional `bool` parameters.
- Doc comments use `///`, one summary sentence, `[brackets]` for references,
  no `@param`.
- Never add `// ignore:` without a reason, and never remove a lint to make a
  change pass. A new lint is enabled only when it is stable, available in the
  minimum SDK, and has zero findings.
- Barrels use `export 'src/x.dart' show A, B;`, one file per line, sorted.
  Imports inside a package are relative.
- Never consume a stream with `await for` in library code: pause, resume and
  cancel must reach the source.

## Code quality rules

| Limit | Value |
|---|---|
| lib file | 300 lines |
| test file | 500 lines |
| method | 40 lines |
| parameters | 5 |
| nesting | 3 levels |
| class | about 15 members |

- One public class (or one sealed family) per file. No `utils`, `helpers` or
  `common` files in `lib/`. No `part` / `part of`.
- A file over its limit never grows. `test/quality/size_limits_test.dart` is a
  ratchet: an allowlist entry may only shrink, and new entries are never
  added. Split the unit instead.
- Tests: one behaviour per test, named after the behaviour; set-up longer than
  about five lines becomes a helper; no network; tests ship in the same commit
  as the code.

## Design rules

- The core knows nothing about HTTP. An adapter attaches the header, recognises
  an auth failure and replays once. It never refreshes by itself.
- Refresh is single-flight: one shared in-flight future, plus a compare of the
  rejected token with the current one.
- A terminal refresh failure (`InvalidGrant`) logs out. A transient one never
  does.
- Public API changes need a `CHANGELOG.md` entry in the changed package.
  Before 1.0 a breaking change is a minor bump; only the changed package is
  bumped.

## Commits

Conventional Commits with a package scope: `feat(token_manager): ...`,
`fix(token_manager_dio): ...`, `refactor(...)`, `test(...)`, `docs: ...`,
`build: ...`. A refactor is its own commit. Branch off `main`; run git from
the repository root.

## Language

Code, comments, docs and commit messages are in English.
````

- [ ] **Step 2: Create `CONTRIBUTING.md`**

````markdown
# Contributing

## Prerequisites

Dart SDK 3.10 or newer.

## Setup

```bash
dart pub get
```

## Everyday commands

```bash
dart format packages
dart analyze packages
cd packages/token_manager && dart test
```

`dart analyze packages` must report no issues, and formatting must be clean,
before a pull request is opened. CI runs the same checks.

## Rules

The code rules, size limits and design rules are in [CLAUDE.md](CLAUDE.md).
They apply to humans and agents alike.

## Tests

Write the failing test first. Tests mirror `lib/src/` under `test/`, use the
fakes in `test/helpers/`, and never touch the network.

## Commits and changelog

Use Conventional Commits with a package scope, for example
`feat(token_manager): add validToken`. Update the `CHANGELOG.md` of every
package whose public behaviour changes.
````

- [ ] **Step 3: Verify formatting is untouched**

Run: `dart format --output=none --set-exit-if-changed packages`
Expected: exit code 0 (documents are not Dart files; this confirms nothing else moved).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md CONTRIBUTING.md
git commit -m "docs: add the project rules and contributing guide

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Size-limits ratchet test

**Files:**
- Create: `packages/token_manager/test/helpers/size_limits.dart` (copied), `packages/token_manager/test/quality/size_limits_test.dart`
- Modify: `packages/token_manager/pubspec.yaml`

**Interfaces:**
- Consumes: Task 2 (lint gate), Task 3 (limits documented).
- Produces: `SizeLimits(String packageRoot)` with `fileFailures({allowlist, permanent})` and `methodFailures({allowlist})`; a failing `dart test` when a file or method grows past its limit.

- [ ] **Step 1: Add the test dependency**

In `packages/token_manager/pubspec.yaml` add after the `dependencies:` block:

```yaml
dev_dependencies:
  test: ^1.31.0
```

Run: `dart pub get`
Expected: `Got dependencies!`.

- [ ] **Step 2: Copy the helper from typed_openapi**

```bash
mkdir -p packages/token_manager/test/helpers packages/token_manager/test/quality
cp /home/genius/projects/typed_openapi/packages/typed_openapi/test/helpers/size_limits.dart \
   packages/token_manager/test/helpers/size_limits.dart
grep -n "typed_openapi\|_vendored" packages/token_manager/test/helpers/size_limits.dart
```

Expected: the `grep` shows only the `_vendored` constant (`'lib/src/load/yaml/'`) and its single use. Remove that constant and the `if` (or condition) that uses it so the helper has no typed_openapi-specific path; the helper must not mention `typed_openapi` anywhere.

- [ ] **Step 3: Write the test with empty allowlists**

`packages/token_manager/test/quality/size_limits_test.dart`:

```dart
/// The size limits of `CLAUDE.md` ("Code quality rules") as a ratchet.
///
/// A file in `lib/` has at most 300 lines, a test file 500, a method 40. A
/// unit over its limit may only be listed below with the size it had when it
/// was listed, and it may only shrink. Never add a new entry, split the unit
/// instead.
library;

import 'package:test/test.dart';

import '../helpers/size_limits.dart';

/// Files over their limit with the lines (`wc -l`) they had when listed.
const Map<String, int> _fileAllowlist = {};

/// Files that are exempt for good: flat catalogs with no logic.
const Set<String> _permanent = {};

/// Methods over 40 lines (`path#Type.name`) with the lines they had.
const Map<String, int> _methodAllowlist = {};

void main() {
  final limits = SizeLimits('.');

  test('no file is over its size limit unless it is allowlisted', () {
    final failures = limits.fileFailures(
      allowlist: _fileAllowlist,
      permanent: _permanent,
    );
    if (failures.isNotEmpty) {
      fail(failures.join('\n'));
    }
  });

  test('no method is over 40 lines unless it is allowlisted', () {
    final failures = limits.methodFailures(allowlist: _methodAllowlist);
    if (failures.isNotEmpty) {
      fail(failures.join('\n'));
    }
  });
}
```

- [ ] **Step 4: Run it and confirm it passes on the current code**

Run: `cd packages/token_manager && dart test test/quality`
Expected: `All tests passed!`.

- [ ] **Step 5: Prove the ratchet bites**

```bash
cd packages/token_manager
python3 -c "print('\n'.join(['// filler'] * 320))" > lib/src/oversize.dart
dart test test/quality
```

Expected: FAIL naming `lib/src/oversize.dart`. Then `rm lib/src/oversize.dart` and re-run: PASS.

- [ ] **Step 6: Gate and commit**

Run: `cd /home/genius/projects/dart_token_manager && dart analyze packages && dart format --output=none --set-exit-if-changed packages`
Expected: no issues, exit 0.

```bash
git add packages/token_manager
git commit -m "test(token_manager): enforce the size limits with a ratchet test

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: Tasks 2 and 4 (analyze gate, test suite).
- Produces: a CI run that mirrors the local commands.

- [ ] **Step 1: Create `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  analyze-test:
    name: Test (${{ matrix.os }}, ${{ matrix.sdk }})
    runs-on: ${{ matrix.os }}
    timeout-minutes: 20
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest]
        sdk: ['3.10.0', stable]
        include:
          - os: macos-latest
            sdk: stable
          - os: windows-latest
            sdk: stable
    steps:
      - uses: actions/checkout@v5
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: ${{ matrix.sdk }}
      - name: Install dependencies
        run: dart pub get
      - name: Check formatting
        if: matrix.sdk == 'stable' && matrix.os == 'ubuntu-latest'
        run: dart format --output=none --set-exit-if-changed packages
      - name: Analyze
        if: matrix.sdk == 'stable' && matrix.os == 'ubuntu-latest'
        run: dart analyze packages
      - name: Test token_manager
        working-directory: packages/token_manager
        run: dart test
```

- [ ] **Step 2: Validate the YAML**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ok')"`
Expected: `ok`. If `actionlint` is installed, also run `actionlint .github/workflows/ci.yml` (expect no output).

- [ ] **Step 3: Commit**

```bash
git add .github
git commit -m "build: add the CI workflow

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Foundations: clock, failures, store, refresher, info, fakes

**Files:**
- Rename: `packages/token_manager/lib/src/token_store.dart` to `legacy_token_store.dart` (class `LegacyTokenStore`)
- Modify: `packages/token_manager/lib/src/token_manager.dart` (import and type name only), `packages/token_manager/lib/token_manager.dart`
- Create: `lib/src/clock.dart`, `lib/src/refresh_failure.dart`, `lib/src/not_authenticated.dart`, `lib/src/token_store.dart`, `lib/src/in_memory_token_store.dart`, `lib/src/token_refresher.dart`, `lib/src/token_info.dart`
- Create: `test/helpers/fake_clock.dart`, `test/helpers/fake_token_store.dart`, `test/helpers/fake_refresher.dart`, `test/in_memory_token_store_test.dart`, `test/refresh_failure_test.dart`

All paths below are relative to `packages/token_manager/`.

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces (exact signatures later tasks use):
  - `class Clock { const Clock(); DateTime now(); }`
  - `sealed class RefreshFailure implements Exception`; `final class InvalidGrant extends RefreshFailure { const InvalidGrant(); }`; `final class Transient extends RefreshFailure { const Transient(this.cause); final Object cause; }`
  - `final class NotAuthenticated implements Exception { const NotAuthenticated(); }`
  - `abstract interface class TokenStore<T> { Future<T?> read(); Future<void> write(T tokens); Future<void> delete(); }`
  - `final class InMemoryTokenStore<T> implements TokenStore<T> { InMemoryTokenStore([T? initial]); }`
  - `abstract interface class TokenRefresher<T> { Future<T> refresh(T current); }`
  - `abstract interface class TokenInfo<T> { DateTime? expiresAt(T tokens); }`
  - Test fakes: `FakeClock(DateTime start)` with `advance(Duration)`; `FakeTokenStore<T>([T? stored])` with `stored`, `reads`, `writes`, `deletes`, `readError`, `writeError`, `log`; `FakeRefresher<T>` with `callCount`, `requested`, `complete(T tokens, {int call = 0})`, `fail(Object error, {int call = 0})`.

- [ ] **Step 1: Free the name `TokenStore` (pure rename)**

```bash
cd packages/token_manager
git mv lib/src/token_store.dart lib/src/legacy_token_store.dart
sed -i 's/\bTokenStore\b/LegacyTokenStore/g' lib/src/legacy_token_store.dart lib/src/token_manager.dart
sed -i "s#'token_store.dart'#'legacy_token_store.dart'#" lib/src/token_manager.dart
dart analyze lib && dart test test/quality
```

Expected: no analyzer errors; `All tests passed!`. (`_tokensStore` is a different identifier and is untouched.)

- [ ] **Step 2: Write the failing tests**

`test/refresh_failure_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/src/not_authenticated.dart';
import 'package:token_manager/src/refresh_failure.dart';

void main() {
  test('InvalidGrant is a RefreshFailure and an Exception', () {
    const failure = InvalidGrant();

    expect(failure, isA<RefreshFailure>());
    expect(failure, isA<Exception>());
  });

  test('Transient keeps the cause and mentions it in its message', () {
    final cause = Exception('offline');
    final failure = Transient(cause);

    expect(failure.cause, same(cause));
    expect(failure.toString(), contains('offline'));
  });

  test('NotAuthenticated is an Exception', () {
    expect(const NotAuthenticated(), isA<Exception>());
  });
}
```

`test/in_memory_token_store_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/src/in_memory_token_store.dart';

void main() {
  test('reads null when nothing was written', () async {
    expect(await InMemoryTokenStore<String>().read(), isNull);
  });

  test('reads the initial value', () async {
    expect(await InMemoryTokenStore<String>('seed').read(), 'seed');
  });

  test('reads what was written', () async {
    final store = InMemoryTokenStore<String>();

    await store.write('token');

    expect(await store.read(), 'token');
  });

  test('delete clears the stored value', () async {
    final store = InMemoryTokenStore<String>('token');

    await store.delete();

    expect(await store.read(), isNull);
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `dart test test/refresh_failure_test.dart test/in_memory_token_store_test.dart`
Expected: FAIL (compile errors: the imported files do not exist).

- [ ] **Step 4: Implement the types**

`lib/src/clock.dart`:

```dart
/// Supplies the current time; replace it in tests to control expiry.
class Clock {
  /// Creates a clock that reads the system time.
  const Clock();

  /// Returns the current time.
  DateTime now() => DateTime.now();
}
```

`lib/src/refresh_failure.dart`:

```dart
/// Why a token refresh failed; thrown by a `TokenRefresher`.
sealed class RefreshFailure implements Exception {
  /// Creates a failure.
  const RefreshFailure();
}

/// The refresh token was rejected for good: the user must sign in again.
final class InvalidGrant extends RefreshFailure {
  /// Creates the failure.
  const InvalidGrant();

  @override
  String toString() => 'InvalidGrant: the refresh token was rejected';
}

/// The refresh failed for a reason that may go away, such as no network.
final class Transient extends RefreshFailure {
  /// Creates the failure wrapping what went wrong.
  const Transient(this.cause);

  /// What went wrong.
  final Object cause;

  @override
  String toString() => 'Transient: $cause';
}
```

`lib/src/not_authenticated.dart`:

```dart
/// No tokens are available: the user is not signed in.
final class NotAuthenticated implements Exception {
  /// Creates the exception.
  const NotAuthenticated();

  @override
  String toString() => 'NotAuthenticated: there are no tokens';
}
```

`lib/src/token_store.dart`:

```dart
/// Persists the tokens of one session; the core does no platform I/O itself.
abstract interface class TokenStore<T> {
  /// Returns the stored tokens, or `null` when there are none.
  Future<T?> read();

  /// Stores [tokens], replacing what was there.
  Future<void> write(T tokens);

  /// Removes the stored tokens.
  Future<void> delete();
}
```

`lib/src/in_memory_token_store.dart`:

```dart
import 'token_store.dart';

/// A [TokenStore] that keeps the tokens in memory only.
final class InMemoryTokenStore<T> implements TokenStore<T> {
  /// Creates a store, optionally holding [initial] tokens.
  InMemoryTokenStore([T? initial]) : _tokens = initial;

  T? _tokens;

  @override
  Future<T?> read() async => _tokens;

  @override
  Future<void> write(T tokens) async {
    _tokens = tokens;
  }

  @override
  Future<void> delete() async {
    _tokens = null;
  }
}
```

`lib/src/token_refresher.dart`:

```dart
/// Exchanges expiring tokens for fresh ones.
abstract interface class TokenRefresher<T> {
  /// Returns new tokens for [current].
  ///
  /// Throws `InvalidGrant` when the refresh token was rejected for good and
  /// `Transient` when the failure may go away. Any other exception is treated
  /// as transient.
  Future<T> refresh(T current);
}
```

`lib/src/token_info.dart`:

```dart
/// Tells when tokens expire.
abstract interface class TokenInfo<T> {
  /// Returns when [tokens] expire, or `null` when they never do.
  DateTime? expiresAt(T tokens);
}
```

- [ ] **Step 5: Add the test fakes**

`test/helpers/fake_clock.dart`:

```dart
import 'package:token_manager/src/clock.dart';

/// A clock whose time only moves when a test says so.
final class FakeClock implements Clock {
  /// Creates a clock reading [start].
  FakeClock(DateTime start) : _now = start;

  DateTime _now;

  @override
  DateTime now() => _now;

  /// Moves the clock forward by [by].
  void advance(Duration by) {
    _now = _now.add(by);
  }
}
```

`test/helpers/fake_token_store.dart`:

```dart
import 'package:token_manager/src/token_store.dart';

/// A store that counts calls, records their order and can be made to fail.
final class FakeTokenStore<T> implements TokenStore<T> {
  /// Creates a store holding [stored].
  FakeTokenStore([this.stored]);

  /// The tokens currently stored.
  T? stored;

  /// How many times [read] was called.
  int reads = 0;

  /// How many times [write] was called.
  int writes = 0;

  /// How many times [delete] was called.
  int deletes = 0;

  /// When set, [read] throws it.
  Exception? readError;

  /// When set, [write] throws it.
  Exception? writeError;

  /// The successful mutations in order: `write` or `delete`.
  final List<String> log = [];

  @override
  Future<T?> read() async {
    reads++;
    final error = readError;
    if (error != null) {
      throw error;
    }
    return stored;
  }

  @override
  Future<void> write(T tokens) async {
    writes++;
    final error = writeError;
    if (error != null) {
      throw error;
    }
    stored = tokens;
    log.add('write');
  }

  @override
  Future<void> delete() async {
    deletes++;
    stored = null;
    log.add('delete');
  }
}
```

`test/helpers/fake_refresher.dart`:

```dart
import 'dart:async';

import 'package:token_manager/src/token_refresher.dart';

/// A refresher whose calls stay pending until a test completes or fails them.
final class FakeRefresher<T> implements TokenRefresher<T> {
  /// The tokens each call was asked to refresh, in call order.
  final List<T> requested = [];

  final List<Completer<T>> _calls = [];

  /// How many times [refresh] was called.
  int get callCount => _calls.length;

  @override
  Future<T> refresh(T current) {
    requested.add(current);
    final call = Completer<T>();
    _calls.add(call);
    return call.future;
  }

  /// Completes call number [call] with [tokens].
  void complete(T tokens, {int call = 0}) => _calls[call].complete(tokens);

  /// Fails call number [call] with [error].
  void fail(Object error, {int call = 0}) => _calls[call].completeError(error);
}
```

- [ ] **Step 6: Export the public types**

Replace `lib/token_manager.dart` with (keep the exports sorted; if `combinators_ordering` or `directives_ordering` complains, reorder):

```dart
library;

export 'src/clock.dart' show Clock;
export 'src/in_memory_token_store.dart' show InMemoryTokenStore;
export 'src/not_authenticated.dart' show NotAuthenticated;
export 'src/refresh_failure.dart' show InvalidGrant, RefreshFailure, Transient;
export 'src/token_info.dart' show TokenInfo;
export 'src/token_info_delegate.dart';
export 'src/token_manager.dart';
export 'src/token_manager_refresh_delegate.dart';
export 'src/token_refresher.dart' show TokenRefresher;
export 'src/token_storage.dart';
export 'src/token_store.dart' show TokenStore;
```

- [ ] **Step 7: Run tests and the gate**

Run: `dart test && cd ../.. && dart analyze packages && dart format --output=none --set-exit-if-changed packages`
Expected: all tests pass; `No issues found!`; exit 0.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(token_manager): add clock, typed refresh failures and store interfaces

Rename the internal store to LegacyTokenStore to free the name.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: State value types and the replaying holder

**Files (relative to `packages/token_manager/`):**
- Create: `lib/src/auth_state.dart`, `lib/src/token_set.dart`, `lib/src/token_set_info.dart`, `lib/src/engine/replay_value.dart`
- Create: `test/auth_state_test.dart`, `test/token_set_test.dart`, `test/engine/replay_value_test.dart`
- Modify: `lib/token_manager.dart`

**Interfaces:**
- Consumes: `TokenInfo<T>` (Task 6).
- Produces:
  - `sealed class AuthState<T> { T? get tokensOrNull; }` with `Unauthenticated<T>()`, `Authenticated<T>(T tokens)`, `Refreshing<T>(T tokens)` (the last two have `final T tokens`).
  - `final class TokenSet { const TokenSet({required String accessToken, String? refreshToken, DateTime? expiresAt}); }` with value equality; `final class TokenSetInfo implements TokenInfo<TokenSet> { const TokenSetInfo(); }`.
  - `final class ReplayValue<S> { ReplayValue(S initial); S get value; Stream<S> get stream; void add(S value); Future<void> close(); }`. `stream` can be listened to many times; each listener first gets the current value, then every later one, then done after `close`.

- [ ] **Step 1: Write the failing tests**

`test/auth_state_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';

void main() {
  test('tokensOrNull is null when unauthenticated', () {
    expect(Unauthenticated<String>().tokensOrNull, isNull);
  });

  test('tokensOrNull returns the tokens when authenticated', () {
    expect(const Authenticated<String>('a').tokensOrNull, 'a');
  });

  test('tokensOrNull returns the tokens while refreshing', () {
    expect(const Refreshing<String>('a').tokensOrNull, 'a');
  });
}
```

`test/token_set_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/src/token_set.dart';
import 'package:token_manager/src/token_set_info.dart';

void main() {
  test('token sets with the same fields are equal', () {
    final expiresAt = DateTime.utc(2026);

    expect(
      TokenSet(accessToken: 'a', refreshToken: 'r', expiresAt: expiresAt),
      TokenSet(accessToken: 'a', refreshToken: 'r', expiresAt: expiresAt),
    );
  });

  test('token sets with different access tokens are not equal', () {
    expect(
      const TokenSet(accessToken: 'a'),
      isNot(const TokenSet(accessToken: 'b')),
    );
  });

  test('TokenSetInfo reads the expiry from the token set', () {
    final expiresAt = DateTime.utc(2026);

    expect(
      const TokenSetInfo().expiresAt(
        TokenSet(accessToken: 'a', expiresAt: expiresAt),
      ),
      expiresAt,
    );
  });

  test('TokenSetInfo returns null when the token set never expires', () {
    expect(
      const TokenSetInfo().expiresAt(const TokenSet(accessToken: 'a')),
      isNull,
    );
  });
}
```

`test/engine/replay_value_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/src/engine/replay_value.dart';

void main() {
  test('a listener gets the current value first', () async {
    final replay = ReplayValue<int>(1);

    await expectLater(replay.stream, emits(1));
  });

  test('a late listener gets the last value, then later ones', () async {
    final replay = ReplayValue<int>(1)..add(2);
    final seen = expectLater(replay.stream, emitsInOrder([2, 3]));

    replay.add(3);

    await seen;
  });

  test('two listeners are independent', () async {
    final replay = ReplayValue<int>(1);
    final first = expectLater(replay.stream, emitsInOrder([1, 2]));
    final second = expectLater(replay.stream, emitsInOrder([1, 2]));

    replay.add(2);

    await first;
    await second;
  });

  test('value reflects the last added value', () {
    final replay = ReplayValue<int>(1)..add(5);

    expect(replay.value, 5);
  });

  test('the stream completes after close', () async {
    final replay = ReplayValue<int>(1);
    final seen = expectLater(replay.stream, emitsInOrder([1, emitsDone]));

    await replay.close();

    await seen;
  });

  test('adding after close is ignored', () async {
    final replay = ReplayValue<int>(1);
    await replay.close();

    replay.add(2);

    expect(replay.value, 1);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd packages/token_manager && dart test test/auth_state_test.dart test/token_set_test.dart test/engine/replay_value_test.dart`
Expected: FAIL (the imported files do not exist).

- [ ] **Step 3: Implement**

`lib/src/auth_state.dart`:

```dart
/// Where a session stands; observed through `TokenManager.states`.
sealed class AuthState<T> {
  /// Creates a state.
  const AuthState();

  /// Returns the tokens of this state, or `null` when there are none.
  T? get tokensOrNull => switch (this) {
    Unauthenticated() => null,
    Authenticated(:final tokens) => tokens,
    Refreshing(:final tokens) => tokens,
  };
}

/// There are no tokens: the user is signed out.
final class Unauthenticated<T> extends AuthState<T> {
  /// Creates the state.
  const Unauthenticated();
}

/// The user is signed in with [tokens].
final class Authenticated<T> extends AuthState<T> {
  /// Creates the state.
  const Authenticated(this.tokens);

  /// The current tokens.
  final T tokens;
}

/// A refresh is running; [tokens] are the ones being replaced.
final class Refreshing<T> extends AuthState<T> {
  /// Creates the state.
  const Refreshing(this.tokens);

  /// The tokens being replaced.
  final T tokens;
}
```

`lib/src/token_set.dart`:

```dart
/// A ready-made token value for apps that need no custom token type.
final class TokenSet {
  /// Creates a token set.
  const TokenSet({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  /// The access token.
  final String accessToken;

  /// The refresh token, if the server issued one.
  final String? refreshToken;

  /// When the access token expires, or `null` if it never does.
  final DateTime? expiresAt;

  @override
  bool operator ==(Object other) =>
      other is TokenSet &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, expiresAt);
}
```

`lib/src/token_set_info.dart`:

```dart
import 'token_info.dart';
import 'token_set.dart';

/// Reads the expiry of a [TokenSet].
final class TokenSetInfo implements TokenInfo<TokenSet> {
  /// Creates the info.
  const TokenSetInfo();

  @override
  DateTime? expiresAt(TokenSet tokens) => tokens.expiresAt;
}
```

`lib/src/engine/replay_value.dart`:

```dart
import 'dart:async';

/// Holds a value and a stream that replays the latest value to each listener.
final class ReplayValue<S> {
  /// Creates a holder whose first value is [initial].
  ReplayValue(S initial) : _value = initial;

  S _value;
  final StreamController<S> _controller = StreamController<S>.broadcast();

  /// The latest value.
  S get value => _value;

  /// A stream that emits the latest value on listen, then every later one.
  Stream<S> get stream => Stream<S>.multi((listener) {
    listener.add(_value);
    final subscription = _controller.stream.listen(
      listener.add,
      onDone: listener.close,
    );
    listener.onCancel = subscription.cancel;
  });

  /// Makes [value] the latest value and sends it to the listeners.
  ///
  /// Does nothing once the holder is closed.
  void add(S value) {
    if (_controller.isClosed) {
      return;
    }
    _value = value;
    _controller.add(value);
  }

  /// Completes every stream; later [add] calls are ignored.
  Future<void> close() => _controller.close();
}
```

- [ ] **Step 4: Export the public types**

Add to `lib/token_manager.dart` (sorted into place):

```dart
export 'src/auth_state.dart'
    show Authenticated, AuthState, Refreshing, Unauthenticated;
export 'src/token_set.dart' show TokenSet;
export 'src/token_set_info.dart' show TokenSetInfo;
```

- [ ] **Step 5: Run tests and the gate**

Run: `dart test && cd ../.. && dart analyze packages && dart format packages && dart format --output=none --set-exit-if-changed packages`
Expected: tests pass; `No issues found!`; exit 0. If `cancel_subscriptions` flags `subscription` in `ReplayValue.stream`, keep the cancel wired through `listener.onCancel` but restructure so the analyzer sees it (for example store the subscription in a local `final` and call `subscription.cancel()` inside an `onCancel` closure) and do not add an ignore.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(token_manager): add AuthState, TokenSet and the replaying value holder

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: TokenEngine: state, lazy load and single-flight refresh

**Files (relative to `packages/token_manager/`):**
- Create: `lib/src/engine/token_engine.dart`, `test/helpers/engine_fixture.dart`, `test/engine/token_engine_test.dart`, `test/engine/token_engine_refresh_test.dart`

**Interfaces:**
- Consumes: `Clock`, `RefreshFailure`/`InvalidGrant`/`Transient`, `NotAuthenticated`, `TokenStore<T>`, `TokenRefresher<T>`, `TokenInfo<T>`, `AuthState<T>`, `ReplayValue<S>`, test fakes.
- Produces (exact):

```dart
final class TokenEngine<T> {
  TokenEngine({
    required TokenStore<T> store,
    required Duration skew,
    required Clock clock,
    TokenRefresher<T>? refresher,
    TokenInfo<T>? info,
  });
  Stream<AuthState<T>> get states;      // replays the last state
  AuthState<T> get state;               // latest state, synchronously
  Future<T?> current();                 // lazy load, no refresh
  Future<T> validToken({T? rejected});  // throws NotAuthenticated, InvalidGrant, Transient
  Future<void> setTokens(T tokens);
  Future<void> logout();
  Future<void> dispose();
  Future<void>? get pendingRefresh;     // null when idle; never completes with an error
}
```

Semantics: tokens are read from the store once, lazily; `validToken` returns the current tokens unless they are inside `skew` of expiry or identical to `rejected`, in which case exactly one shared refresh runs; a `rejected` token that is no longer the current one never triggers a refresh; `InvalidGrant` clears the store and emits `Unauthenticated`; `Transient` (or any other `Exception` from the refresher) restores `Authenticated(old)` and throws `Transient`; a refresh that finishes after `setTokens`, `logout` or `dispose` is discarded.

- [ ] **Step 1: Add the shared test fixture**

`test/helpers/engine_fixture.dart`:

```dart
import 'package:token_manager/src/engine/token_engine.dart';
import 'package:token_manager/src/token_set.dart';
import 'package:token_manager/src/token_set_info.dart';

import 'fake_clock.dart';
import 'fake_refresher.dart';
import 'fake_token_store.dart';

/// Wires a [TokenEngine] to fakes and builds token sets relative to its clock.
final class EngineFixture {
  /// Creates a fixture whose clock starts at 2026-01-01 UTC.
  EngineFixture()
    : clock = FakeClock(DateTime.utc(2026)),
      store = FakeTokenStore<TokenSet>(),
      refresher = FakeRefresher<TokenSet>();

  /// The engine's clock.
  final FakeClock clock;

  /// The engine's store.
  final FakeTokenStore<TokenSet> store;

  /// The engine's refresher.
  final FakeRefresher<TokenSet> refresher;

  /// Builds an engine with a 30 second skew.
  TokenEngine<TokenSet> engine({bool withRefresher = true}) {
    return TokenEngine<TokenSet>(
      store: store,
      skew: const Duration(seconds: 30),
      clock: clock,
      refresher: withRefresher ? refresher : null,
      info: const TokenSetInfo(),
    );
  }

  /// Builds tokens that expire [life] after the fixture's current time.
  TokenSet tokens(Duration life, {String access = 'a'}) {
    return TokenSet(
      accessToken: access,
      refreshToken: 'r',
      expiresAt: clock.now().add(life),
    );
  }
}
```

#### Cycle 1: state, lazy load, set and logout

- [ ] **Step 2: Write the failing tests**

`test/engine/token_engine_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/not_authenticated.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';

void main() {
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  test('starts unauthenticated and replays the state to late listeners',
      () async {
    final engine = fixture.engine();

    expect(engine.state, isA<Unauthenticated<TokenSet>>());
    await expectLater(
      engine.states,
      emits(isA<Unauthenticated<TokenSet>>()),
    );
  });

  test('current loads the stored tokens once', () async {
    final stored = fixture.tokens(const Duration(hours: 1));
    fixture.store.stored = stored;
    final engine = fixture.engine();

    expect(await engine.current(), same(stored));
    expect(await engine.current(), same(stored));

    expect(fixture.store.reads, 1);
    expect(engine.state, isA<Authenticated<TokenSet>>());
  });

  test('current is null when nothing is stored', () async {
    expect(await fixture.engine().current(), isNull);
  });

  test('a failed read is retried on the next call', () async {
    final stored = fixture.tokens(const Duration(hours: 1));
    fixture.store
      ..stored = stored
      ..readError = Exception('disk');
    final engine = fixture.engine();

    await expectLater(engine.current(), throwsException);
    fixture.store.readError = null;

    expect(await engine.current(), same(stored));
    expect(fixture.store.reads, 2);
  });

  test('setTokens persists the tokens and emits Authenticated', () async {
    final engine = fixture.engine();
    final tokens = fixture.tokens(const Duration(hours: 1));

    await engine.setTokens(tokens);

    expect(fixture.store.stored, same(tokens));
    expect(engine.state.tokensOrNull, same(tokens));
  });

  test('setTokens does not emit when the store fails', () async {
    fixture.store.writeError = Exception('full');
    final engine = fixture.engine();

    await expectLater(
      engine.setTokens(fixture.tokens(const Duration(hours: 1))),
      throwsException,
    );

    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('logout deletes the tokens and emits Unauthenticated', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(hours: 1)));

    await engine.logout();

    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('validToken throws NotAuthenticated without tokens', () async {
    await expectLater(
      fixture.engine().validToken(),
      throwsA(isA<NotAuthenticated>()),
    );
  });

  test('validToken returns the stored tokens while they are valid', () async {
    final stored = fixture.tokens(const Duration(hours: 1));
    fixture.store.stored = stored;

    expect(await fixture.engine().validToken(), same(stored));
    expect(fixture.refresher.callCount, 0);
  });

  test('dispose completes the states stream', () async {
    final engine = fixture.engine();

    await engine.dispose();

    await expectLater(
      engine.states,
      emitsInOrder([isA<Unauthenticated<TokenSet>>(), emitsDone]),
    );
  });
}
```

- [ ] **Step 3: Run it to see it fail**

Run: `cd packages/token_manager && dart test test/engine/token_engine_test.dart`
Expected: FAIL (`token_engine.dart` does not exist).

- [ ] **Step 4: Implement cycle 1**

`lib/src/engine/token_engine.dart`:

```dart
import 'dart:async';

import '../auth_state.dart';
import '../clock.dart';
import '../not_authenticated.dart';
import '../token_info.dart';
import '../token_refresher.dart';
import '../token_store.dart';
import 'replay_value.dart';

/// Loads, persists and refreshes the tokens of one session.
///
/// `TokenManager` delegates all of its work here.
final class TokenEngine<T> {
  /// Creates an engine over [store].
  TokenEngine({
    required TokenStore<T> store,
    required Duration skew,
    required Clock clock,
    TokenRefresher<T>? refresher,
    TokenInfo<T>? info,
  }) : _store = store,
       _skew = skew,
       _clock = clock,
       _refresher = refresher,
       _info = info;

  final TokenStore<T> _store;
  final Duration _skew;
  final Clock _clock;
  final TokenRefresher<T>? _refresher;
  final TokenInfo<T>? _info;
  final ReplayValue<AuthState<T>> _states =
      ReplayValue<AuthState<T>>(Unauthenticated<T>());

  Future<void>? _loading;
  Future<void> _tail = Future<void>.value();
  int _epoch = 0;
  bool _disposed = false;

  /// Emits the latest state on listen, then every change.
  Stream<AuthState<T>> get states => _states.stream;

  /// The latest state.
  AuthState<T> get state => _states.value;

  /// Returns the current tokens without refreshing them.
  Future<T?> current() async {
    await _load();
    return state.tokensOrNull;
  }

  /// Returns tokens that are valid now.
  Future<T> validToken() async {
    await _load();
    final tokens = state.tokensOrNull;
    if (tokens == null) {
      throw const NotAuthenticated();
    }
    return tokens;
  }

  /// Stores [tokens] and makes them the current session.
  Future<void> setTokens(T tokens) async {
    await _load();
    await _exclusive<void>(() async {
      await _store.write(tokens);
      _epoch++;
      _emit(Authenticated<T>(tokens));
    });
  }

  /// Removes the tokens and signs the session out.
  Future<void> logout() async {
    await _load();
    await _exclusive<void>(_clear);
  }

  /// Stops emitting; work that finishes later is discarded.
  Future<void> dispose() async {
    _disposed = true;
    _epoch++;
    await _states.close();
  }

  Future<void> _clear() async {
    await _store.delete();
    _epoch++;
    _emit(Unauthenticated<T>());
  }

  void _emit(AuthState<T> next) {
    if (_disposed) {
      return;
    }
    _states.add(next);
  }

  Future<void> _load() async {
    final loading = _loading ??= _loadOnce();
    try {
      await loading;
    } on Exception {
      if (identical(_loading, loading)) {
        _loading = null;
      }
      rethrow;
    }
  }

  Future<void> _loadOnce() async {
    final stored = await _store.read();
    if (stored != null) {
      _emit(Authenticated<T>(stored));
    }
  }

  /// Runs [action] after every earlier exclusive action has finished.
  Future<R> _exclusive<R>(Future<R> Function() action) {
    final run = _tail.then<R>((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}
```

- [ ] **Step 5: Run cycle 1 tests**

Run: `dart test test/engine/token_engine_test.dart`
Expected: PASS (10 tests). Do not run `dart analyze` yet: the refresh fields are used in cycle 2.

#### Cycle 2: refresh

- [ ] **Step 6: Write the failing refresh tests**

`test/engine/token_engine_refresh_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/not_authenticated.dart';
import 'package:token_manager/src/refresh_failure.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';

void main() {
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('refreshes tokens inside the skew and persists the result', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final pending = engine.validToken();
    await settle();
    fixture.refresher.complete(fresh);

    expect(await pending, same(fresh));
    expect(fixture.store.stored, same(fresh));
    expect(engine.state, isA<Authenticated<TokenSet>>());
  });

  test('emits Refreshing while a refresh runs', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));

    final pending = engine.validToken();
    await settle();

    expect(engine.state, isA<Refreshing<TokenSet>>());
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await pending;
  });

  test('concurrent callers share one refresh', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final first = engine.validToken();
    final second = engine.validToken();
    await settle();
    fixture.refresher.complete(fresh);

    expect(fixture.refresher.callCount, 1);
    expect(await first, same(fresh));
    expect(await second, same(fresh));
  });

  test('a rejected current token is refreshed even if it looks valid',
      () async {
    final engine = fixture.engine();
    final current = fixture.tokens(const Duration(hours: 1));
    await engine.setTokens(current);
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final pending = engine.validToken(rejected: current);
    await settle();
    fixture.refresher.complete(fresh);

    expect(await pending, same(fresh));
    expect(fixture.refresher.requested.single, same(current));
  });

  test('a rejected token that is no longer current does not refresh',
      () async {
    final engine = fixture.engine();
    final current = fixture.tokens(const Duration(hours: 1));
    await engine.setTokens(current);
    final old = fixture.tokens(const Duration(hours: 1), access: 'old');

    expect(await engine.validToken(rejected: old), same(current));
    expect(fixture.refresher.callCount, 0);
  });

  test('without a refresher the tokens are returned as they are', () async {
    final engine = fixture.engine(withRefresher: false);
    final expiring = fixture.tokens(const Duration(seconds: 1));
    await engine.setTokens(expiring);

    expect(await engine.validToken(rejected: expiring), same(expiring));
  });

  test('InvalidGrant clears the session and fails every waiter', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));

    final first = expectLater(
      engine.validToken(),
      throwsA(isA<InvalidGrant>()),
    );
    final second = expectLater(
      engine.validToken(),
      throwsA(isA<InvalidGrant>()),
    );
    await settle();
    fixture.refresher.fail(const InvalidGrant());
    await first;
    await second;

    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('Transient keeps the session and the next call retries', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(seconds: 10));
    await engine.setTokens(old);

    final failed = expectLater(
      engine.validToken(),
      throwsA(isA<Transient>()),
    );
    await settle();
    fixture.refresher.fail(const Transient('offline'));
    await failed;

    expect(fixture.store.deletes, 0);
    expect(engine.state.tokensOrNull, same(old));
    final retry = engine.validToken();
    await settle();
    expect(fixture.refresher.callCount, 2);
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)), call: 1);
    await retry;
  });

  test('an exception that is not a RefreshFailure is transient', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(seconds: 10));
    await engine.setTokens(old);

    final failed = expectLater(
      engine.validToken(),
      throwsA(
        isA<Transient>().having(
          (failure) => failure.cause,
          'cause',
          isA<FormatException>(),
        ),
      ),
    );
    await settle();
    fixture.refresher.fail(const FormatException('bad body'));
    await failed;

    expect(fixture.store.deletes, 0);
    expect(engine.state.tokensOrNull, same(old));
  });

  test('a refreshed token already inside the skew is returned, not looped on',
      () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final shortLived = fixture.tokens(const Duration(seconds: 5), access: 'b');

    final pending = engine.validToken().timeout(const Duration(seconds: 2));
    await settle();
    fixture.refresher.complete(shortLived);

    expect(await pending, same(shortLived));
    expect(fixture.refresher.callCount, 1);
  });

  test('setTokens during a refresh discards the refresh result', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final loggedIn = fixture.tokens(const Duration(hours: 2), access: 'login');

    final pending = engine.validToken();
    await settle();
    await engine.setTokens(loggedIn);
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));

    expect(await pending, same(loggedIn));
    expect(fixture.store.stored, same(loggedIn));
  });

  test('logout during a refresh discards the refresh result', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));

    final pending = expectLater(
      engine.validToken(),
      throwsA(isA<NotAuthenticated>()),
    );
    await settle();
    await engine.logout();
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await pending;

    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('dispose during a refresh writes nothing afterwards', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(seconds: 10));
    await engine.setTokens(old);

    final pending = engine.validToken();
    await settle();
    await engine.dispose();
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));

    expect(await pending, same(old));
    expect(fixture.store.stored, same(old));
  });

  test('a store failure after a refresh surfaces and the next call retries',
      () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(seconds: 10));
    await engine.setTokens(old);
    fixture.store.writeError = Exception('disk full');

    final failed = expectLater(engine.validToken(), throwsException);
    await settle();
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await failed;

    expect(engine.state.tokensOrNull, same(old));
    fixture.store.writeError = null;
    final retry = engine.validToken();
    await settle();
    expect(fixture.refresher.callCount, 2);
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)), call: 1);
    await retry;
  });

  test('a waiter that gives up does not cancel the shared refresh', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    final impatient = expectLater(
      engine.validToken().timeout(const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
    final patient = engine.validToken();
    await impatient;
    fixture.refresher.complete(fresh);

    expect(await patient, same(fresh));
  });

  test('pendingRefresh is null when idle and completes with the refresh',
      () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    expect(engine.pendingRefresh, isNull);

    final refresh = engine.validToken();
    await settle();
    final pending = engine.pendingRefresh;
    expect(pending, isNotNull);

    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await refresh;
    await pending;
    expect(engine.pendingRefresh, isNull);
  });
}
```

- [ ] **Step 7: Run them to see them fail**

Run: `dart test test/engine/token_engine_refresh_test.dart`
Expected: FAIL (`validToken` has no `rejected` parameter, `pendingRefresh` is missing).

- [ ] **Step 8: Implement cycle 2**

In `lib/src/engine/token_engine.dart`:

(a) Add the import `import '../refresh_failure.dart';` after `import '../not_authenticated.dart';`.

(b) Add the field `Future<T>? _flight;` after `Future<void> _tail = Future<void>.value();`.

(c) Replace the `validToken` method with:

```dart
  /// Returns tokens that are valid now, refreshing them when needed.
  ///
  /// [rejected] is a token a server just refused: it forces a refresh unless
  /// another caller already replaced it. Concurrent callers share one refresh.
  Future<T> validToken({T? rejected}) async {
    await _load();
    final tokens = state.tokensOrNull;
    if (tokens == null) {
      throw const NotAuthenticated();
    }
    final refresher = _refresher;
    if (refresher == null || !_needsRefresh(tokens, rejected)) {
      return tokens;
    }
    final running = _flight;
    if (running != null) {
      return running;
    }
    final flight = _refresh(refresher, tokens);
    _flight = flight;
    _forgetWhenDone(flight);
    return flight;
  }

  /// Completes when the refresh in flight ends, never with an error; `null`
  /// when no refresh is running.
  Future<void>? get pendingRefresh =>
      _flight?.then<void>((_) {}, onError: (_) {});
```

(d) Add these private members before `_exclusive`:

```dart
  bool _needsRefresh(T tokens, T? rejected) {
    return identical(tokens, rejected) || _isExpiring(tokens);
  }

  bool _isExpiring(T tokens) {
    final expiresAt = _info?.expiresAt(tokens);
    if (expiresAt == null) {
      return false;
    }
    return !_clock.now().add(_skew).isBefore(expiresAt);
  }

  void _forgetWhenDone(Future<T> flight) {
    void forget() {
      if (identical(_flight, flight)) {
        _flight = null;
      }
    }

    flight.then<void>((_) => forget(), onError: (_) => forget());
  }

  Future<T> _refresh(TokenRefresher<T> refresher, T current) async {
    final epoch = _epoch;
    _emit(Refreshing<T>(current));
    final T refreshed;
    try {
      refreshed = await refresher.refresh(current);
    } on InvalidGrant {
      await _exclusive<void>(() async {
        if (epoch == _epoch) {
          await _clear();
        }
      });
      rethrow;
    } on RefreshFailure {
      _restore(epoch, current);
      rethrow;
    } on Exception catch (error) {
      _restore(epoch, current);
      throw Transient(error);
    }
    final committed = await _commit(epoch, current, refreshed);
    return committed ?? _supersededBy();
  }

  /// Persists [refreshed] unless the session changed since [epoch].
  Future<T?> _commit(int epoch, T previous, T refreshed) {
    return _exclusive<T?>(() async {
      if (epoch != _epoch) {
        return null;
      }
      try {
        await _store.write(refreshed);
      } on Exception {
        _emit(Authenticated<T>(previous));
        rethrow;
      }
      _emit(Authenticated<T>(refreshed));
      return refreshed;
    });
  }

  void _restore(int epoch, T current) {
    if (epoch == _epoch) {
      _emit(Authenticated<T>(current));
    }
  }

  T _supersededBy() {
    final tokens = state.tokensOrNull;
    if (tokens == null) {
      throw const NotAuthenticated();
    }
    return tokens;
  }
```

- [ ] **Step 9: Run both engine test files**

Run: `dart test test/engine`
Expected: all pass (10 + 16 tests).

- [ ] **Step 10: Gate**

Run: `cd ../.. && dart format packages && dart analyze packages && dart format --output=none --set-exit-if-changed packages && (cd packages/token_manager && dart test)`
Expected: `No issues found!`, exit 0, all tests pass. The engine file must stay under 300 lines and each method under 40 (the ratchet test checks it).

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat(token_manager): add the token engine with single-flight refresh

validToken shares one in-flight refresh, skips it when the rejected token
is no longer current, separates InvalidGrant from transient failures and
discards a refresh that finishes after setTokens, logout or dispose.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: authorize: send with a token, replay once

**Files (relative to `packages/token_manager/`):**
- Create: `lib/src/engine/authorized_call.dart`, `test/engine/authorized_call_test.dart`

**Interfaces:**
- Consumes: `TokenEngine<T>.validToken({T? rejected})` (Task 8), `EngineFixture` (Task 8).
- Produces:

```dart
final class AuthorizedCall<T> {
  AuthorizedCall(TokenEngine<T> engine);
  Future<R> run<R>(
    Future<R> Function(T tokens) send, {
    required bool Function(Object error) isAuthFailure,
  });
}
```

`run` sends with `validToken()`. If `send` throws an `Exception` for which `isAuthFailure` is true, it asks `validToken(rejected: used)`; when that returns the same instance (no refresh was possible) the original error is rethrown, otherwise it sends exactly once more. A second failure, and every non-auth failure, propagates.

- [ ] **Step 1: Write the failing tests**

`test/engine/authorized_call_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/src/engine/authorized_call.dart';
import 'package:token_manager/src/refresh_failure.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';

final class _Unauthorized implements Exception {
  const _Unauthorized();
}

void main() {
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  bool isUnauthorized(Object error) => error is _Unauthorized;

  test('sends once with the current tokens', () async {
    final tokens = fixture.tokens(const Duration(hours: 1));
    final engine = fixture.engine();
    await engine.setTokens(tokens);
    final sent = <TokenSet>[];

    final result = await AuthorizedCall(engine).run<String>(
      (used) async {
        sent.add(used);
        return 'ok';
      },
      isAuthFailure: isUnauthorized,
    );

    expect(result, 'ok');
    expect(sent.single, same(tokens));
  });

  test('replays once with refreshed tokens after an auth failure', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(hours: 1));
    await engine.setTokens(old);
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    final sent = <TokenSet>[];

    final result = AuthorizedCall(engine).run<String>(
      (used) async {
        sent.add(used);
        if (identical(used, old)) {
          throw const _Unauthorized();
        }
        return 'ok';
      },
      isAuthFailure: isUnauthorized,
    );
    await settle();
    fixture.refresher.complete(fresh);

    expect(await result, 'ok');
    expect(sent, [same(old), same(fresh)]);
  });

  test('a second auth failure propagates after exactly one replay', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(hours: 1)));
    var sends = 0;

    final result = expectLater(
      AuthorizedCall(engine).run<String>(
        (used) async {
          sends++;
          throw const _Unauthorized();
        },
        isAuthFailure: isUnauthorized,
      ),
      throwsA(isA<_Unauthorized>()),
    );
    await settle();
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await result;

    expect(sends, 2);
    expect(fixture.refresher.callCount, 1);
  });

  test('a failure that is not an auth failure never refreshes', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(hours: 1)));

    await expectLater(
      AuthorizedCall(engine).run<String>(
        (used) async => throw StateError('boom'),
        isAuthFailure: isUnauthorized,
      ),
      throwsStateError,
    );

    expect(fixture.refresher.callCount, 0);
  });

  test('concurrent auth failures cause one refresh', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(hours: 1));
    await engine.setTokens(old);
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    Future<String> call() => AuthorizedCall(engine).run<String>(
      (used) async {
        if (identical(used, old)) {
          throw const _Unauthorized();
        }
        return 'ok';
      },
      isAuthFailure: isUnauthorized,
    );

    final first = call();
    final second = call();
    await settle();
    fixture.refresher.complete(fresh);

    expect(await first, 'ok');
    expect(await second, 'ok');
    expect(fixture.refresher.callCount, 1);
  });

  test('tokens replaced during the call are used for the replay without a '
      'refresh', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(hours: 1));
    await engine.setTokens(old);
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    final sent = <TokenSet>[];

    final result = await AuthorizedCall(engine).run<String>(
      (used) async {
        sent.add(used);
        if (identical(used, old)) {
          await engine.setTokens(fresh);
          throw const _Unauthorized();
        }
        return 'ok';
      },
      isAuthFailure: isUnauthorized,
    );

    expect(result, 'ok');
    expect(sent, [same(old), same(fresh)]);
    expect(fixture.refresher.callCount, 0);
  });

  test('without a refresher the original auth failure is rethrown', () async {
    final engine = fixture.engine(withRefresher: false);
    await engine.setTokens(fixture.tokens(const Duration(hours: 1)));
    var sends = 0;

    await expectLater(
      AuthorizedCall(engine).run<String>(
        (used) async {
          sends++;
          throw const _Unauthorized();
        },
        isAuthFailure: isUnauthorized,
      ),
      throwsA(isA<_Unauthorized>()),
    );

    expect(sends, 1);
  });

  test('InvalidGrant from the refresh propagates to the caller', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(hours: 1)));

    final result = expectLater(
      AuthorizedCall(engine).run<String>(
        (used) async => throw const _Unauthorized(),
        isAuthFailure: isUnauthorized,
      ),
      throwsA(isA<InvalidGrant>()),
    );
    await settle();
    fixture.refresher.fail(const InvalidGrant());
    await result;
  });
}
```

- [ ] **Step 2: Run to see it fail**

Run: `cd packages/token_manager && dart test test/engine/authorized_call_test.dart`
Expected: FAIL (`authorized_call.dart` does not exist).

- [ ] **Step 3: Implement**

`lib/src/engine/authorized_call.dart`:

```dart
import 'token_engine.dart';

/// Sends a call with valid tokens and replays it once after an auth failure.
final class AuthorizedCall<T> {
  /// Creates a call helper over [engine].
  AuthorizedCall(this._engine);

  final TokenEngine<T> _engine;

  /// Runs [send] with valid tokens.
  ///
  /// When [send] throws an exception for which [isAuthFailure] is true, the
  /// tokens it used are reported as rejected and [send] runs one more time
  /// with the replacement. A second failure, and any other failure, propagates.
  /// When no replacement exists the original failure is rethrown.
  Future<R> run<R>(
    Future<R> Function(T tokens) send, {
    required bool Function(Object error) isAuthFailure,
  }) async {
    final used = await _engine.validToken();
    try {
      return await send(used);
    } on Exception catch (error) {
      if (!isAuthFailure(error)) {
        rethrow;
      }
      final renewed = await _engine.validToken(rejected: used);
      if (identical(renewed, used)) {
        rethrow;
      }
      return await send(renewed);
    }
  }
}
```

- [ ] **Step 4: Run tests and the gate**

Run: `dart test test/engine/authorized_call_test.dart && cd ../.. && dart format packages && dart analyze packages && dart format --output=none --set-exit-if-changed packages`
Expected: all pass; `No issues found!`; exit 0.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(token_manager): add AuthorizedCall with a single replay

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 10: RelayStream: stream relay with a faithful lifecycle

**Files (relative to `packages/token_manager/`):**
- Create: `lib/src/engine/relay_stream.dart`, `test/engine/relay_stream_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (it takes functions, so it is testable on its own).
- Produces:

```dart
final class RelayStream<T, R> {
  RelayStream({
    required Future<T> Function() acquire,
    required Future<T> Function(T rejected) renew,
    required Stream<R> Function(T tokens) open,
    required bool Function(Object error) isAuthFailure,
  });
  Stream<R> get stream; // single-subscription; nothing happens until listened to
}
```

Behaviour: on listen it calls `acquire()`, then `open(tokens)` and subscribes with `listen` (never `await for`). Pause, resume and cancel reach the source subscription; a pause requested before the source exists is applied when it opens; a cancel before the token arrives means `open` is never called. If the source fails with an auth failure before any event was delivered, it cancels the source, calls `renew(used)` and reopens once with the result; when `renew` returns the same instance, or fails, or the second source fails with an auth error, the error is forwarded. Done from the source closes the relayed stream.

- [ ] **Step 1: Write the failing tests**

`test/engine/relay_stream_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager/src/engine/relay_stream.dart';

final class _Unauthorized implements Exception {
  const _Unauthorized();
}

final class _Source {
  _Source(this.tokens) {
    controller.onCancel = () => cancelled = true;
  }

  final String tokens;
  final StreamController<int> controller = StreamController<int>();
  bool cancelled = false;
}

void main() {
  late List<_Source> sources;
  late int renewCalls;

  setUp(() {
    sources = [];
    renewCalls = 0;
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Stream<int> relayed({
    Future<String> Function()? acquire,
    Future<String> Function(String rejected)? renew,
  }) {
    return RelayStream<String, int>(
      acquire: acquire ?? () async => 'a',
      renew: renew ??
          (rejected) async {
            renewCalls++;
            return 'b';
          },
      open: (tokens) {
        final source = _Source(tokens);
        sources.add(source);
        return source.controller.stream;
      },
      isAuthFailure: (error) => error is _Unauthorized,
    ).stream;
  }

  test('opens the source only when listened to and relays events', () async {
    final stream = relayed();
    await settle();
    expect(sources, isEmpty);

    final received = <int>[];
    final subscription = stream.listen(received.add);
    await settle();
    sources.single.controller
      ..add(1)
      ..add(2);
    await settle();

    expect(sources.single.tokens, 'a');
    expect(received, [1, 2]);
    await subscription.cancel();
  });

  test('cancelling before the token arrives never opens the source',
      () async {
    final token = Completer<String>();
    final subscription = relayed(acquire: () => token.future).listen((_) {});
    await settle();

    await subscription.cancel();
    token.complete('a');
    await settle();

    expect(sources, isEmpty);
  });

  test('a pause requested before the source opens is applied to it',
      () async {
    final token = Completer<String>();
    final subscription = relayed(acquire: () => token.future).listen((_) {});
    await settle();

    subscription.pause();
    token.complete('a');
    await settle();

    expect(sources.single.controller.isPaused, isTrue);
    await subscription.cancel();
  });

  test('pause and resume reach the source', () async {
    final subscription = relayed().listen((_) {});
    await settle();

    subscription.pause();
    expect(sources.single.controller.isPaused, isTrue);

    subscription.resume();
    expect(sources.single.controller.isPaused, isFalse);
    await subscription.cancel();
  });

  test('cancel reaches the source', () async {
    final subscription = relayed().listen((_) {});
    await settle();

    await subscription.cancel();

    expect(sources.single.cancelled, isTrue);
  });

  test('an auth failure before the first event renews and reopens once',
      () async {
    final received = <int>[];
    final errors = <Object>[];
    final subscription = relayed().listen(received.add, onError: errors.add);
    await settle();

    sources[0].controller.addError(const _Unauthorized());
    await settle();
    sources[1].controller.add(7);
    await settle();

    expect(sources.map((source) => source.tokens), ['a', 'b']);
    expect(sources[0].cancelled, isTrue);
    expect(renewCalls, 1);
    expect(received, [7]);
    expect(errors, isEmpty);
    await subscription.cancel();
  });

  test('an auth failure after the first event is forwarded', () async {
    final received = <int>[];
    final errors = <Object>[];
    final subscription = relayed().listen(received.add, onError: errors.add);
    await settle();

    sources.single.controller
      ..add(1)
      ..addError(const _Unauthorized());
    await settle();

    expect(received, [1]);
    expect(errors.single, isA<_Unauthorized>());
    expect(renewCalls, 0);
    await subscription.cancel();
  });

  test('a second auth failure after the replay is forwarded', () async {
    final errors = <Object>[];
    final subscription = relayed().listen((_) {}, onError: errors.add);
    await settle();

    sources[0].controller.addError(const _Unauthorized());
    await settle();
    sources[1].controller.addError(const _Unauthorized());
    await settle();

    expect(errors.single, isA<_Unauthorized>());
    expect(renewCalls, 1);
    await subscription.cancel();
  });

  test('the error is forwarded and the stream ends when renew returns the '
      'same tokens', () async {
    final errors = <Object>[];
    var done = false;
    final subscription = relayed(renew: (rejected) async => rejected).listen(
      (_) {},
      onError: errors.add,
      onDone: () => done = true,
    );
    await settle();

    sources.single.controller.addError(const _Unauthorized());
    await settle();

    expect(errors.single, isA<_Unauthorized>());
    expect(done, isTrue);
    expect(sources, hasLength(1));
    await subscription.cancel();
  });

  test('a failure to acquire tokens becomes an error and ends the stream',
      () async {
    final errors = <Object>[];
    var done = false;
    final subscription = relayed(
      acquire: () async => throw Exception('offline'),
    ).listen((_) {}, onError: errors.add, onDone: () => done = true);
    await settle();

    expect(errors.single, isA<Exception>());
    expect(done, isTrue);
    expect(sources, isEmpty);
    await subscription.cancel();
  });

  test('the relayed stream ends when the source ends', () async {
    var done = false;
    final subscription = relayed().listen((_) {}, onDone: () => done = true);
    await settle();

    await sources.single.controller.close();
    await settle();

    expect(done, isTrue);
    await subscription.cancel();
  });
}
```

- [ ] **Step 2: Run to see it fail**

Run: `cd packages/token_manager && dart test test/engine/relay_stream_test.dart`
Expected: FAIL (`relay_stream.dart` does not exist).

- [ ] **Step 3: Implement**

`lib/src/engine/relay_stream.dart`:

```dart
import 'dart:async';

/// Relays a stream that needs valid tokens to open.
///
/// The source is subscribed with `listen`, never `await for`, so pause, resume
/// and cancel reach it. An auth failure before the first event reopens the
/// source once with renewed tokens; later failures are forwarded.
final class RelayStream<T, R> {
  /// Creates a relay; nothing happens until [stream] is listened to.
  RelayStream({
    required Future<T> Function() acquire,
    required Future<T> Function(T rejected) renew,
    required Stream<R> Function(T tokens) open,
    required bool Function(Object error) isAuthFailure,
  }) : _acquire = acquire,
       _renew = renew,
       _open = open,
       _isAuthFailure = isAuthFailure {
    _controller = StreamController<R>(
      onListen: _start,
      onPause: _pause,
      onResume: _resume,
      onCancel: _cancel,
    );
  }

  final Future<T> Function() _acquire;
  final Future<T> Function(T rejected) _renew;
  final Stream<R> Function(T tokens) _open;
  final bool Function(Object error) _isAuthFailure;

  // Assigned once in the constructor body: its callbacks need `this`.
  late final StreamController<R> _controller;

  StreamSubscription<R>? _source;
  T? _used;
  bool _cancelled = false;
  bool _delivered = false;
  bool _replayed = false;

  /// The relayed stream; it supports a single subscription.
  Stream<R> get stream => _controller.stream;

  Future<void> _start() async {
    try {
      final tokens = await _acquire();
      if (_cancelled) {
        return;
      }
      _attach(tokens);
    } on Exception catch (error, stackTrace) {
      _finish(error, stackTrace);
    }
  }

  void _attach(T tokens) {
    _used = tokens;
    final source = _open(tokens).listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
    );
    _source = source;
    if (_controller.isPaused) {
      source.pause();
    }
  }

  void _onData(R event) {
    _delivered = true;
    _controller.add(event);
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (_delivered || _replayed || !_isAuthFailure(error)) {
      _controller.addError(error, stackTrace);
      return;
    }
    unawaited(_replay(error, stackTrace));
  }

  void _onDone() {
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }

  Future<void> _replay(Object error, StackTrace stackTrace) async {
    _replayed = true;
    final used = _used;
    final stale = _source;
    _source = null;
    if (used == null) {
      _finish(error, stackTrace);
      return;
    }
    try {
      await stale?.cancel();
      final renewed = await _renew(used);
      if (_cancelled) {
        return;
      }
      if (identical(renewed, used)) {
        _finish(error, stackTrace);
        return;
      }
      _attach(renewed);
    } on Exception catch (failure, failureTrace) {
      _finish(failure, failureTrace);
    }
  }

  void _finish(Object error, StackTrace stackTrace) {
    if (_controller.isClosed) {
      return;
    }
    _controller.addError(error, stackTrace);
    unawaited(_controller.close());
  }

  void _pause() => _source?.pause();

  void _resume() => _source?.resume();

  Future<void> _cancel() {
    _cancelled = true;
    final source = _source;
    _source = null;
    return source?.cancel() ?? Future<void>.value();
  }
}
```

- [ ] **Step 4: Run tests and the gate**

Run: `dart test test/engine/relay_stream_test.dart && cd ../.. && dart format packages && dart analyze packages && dart format --output=none --set-exit-if-changed packages`
Expected: all pass; `No issues found!`; exit 0. If `cancel_subscriptions` flags `_source`, it is cancelled in `_cancel` and replaced in `_replay`; restructure so the analyzer sees the `cancel()` call, never ignore.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(token_manager): add RelayStream for lifecycle-safe stream relaying

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 11: TokenManager: new API plus the deprecated facade

**Files (relative to `packages/token_manager/`):**
- Rewrite: `lib/src/token_manager.dart`
- Create: `lib/src/revoked_tokens_exception.dart`, `lib/src/legacy/storage_token_store.dart`, `lib/src/legacy/delegate_token_refresher.dart`, `test/legacy/token_manager_legacy_test.dart`, `test/token_manager_test.dart`
- Modify: `lib/src/token_storage.dart`, `lib/src/token_manager_refresh_delegate.dart`, `lib/src/token_info_delegate.dart`, `lib/token_manager.dart`, `pubspec.yaml`, `example/main.dart`, plus `ignore_for_file` headers in `packages/token_manager_dio/lib` and `packages/token_manager_grpc/lib` files that use the deprecated API
- Delete: `lib/src/legacy_token_store.dart`

**Interfaces:**
- Consumes: `TokenEngine<T>` (incl. `pendingRefresh`), `AuthorizedCall<T>`, `RelayStream<T, R>`, `Clock`, `TokenStore<T>`, `TokenRefresher<T>`, `TokenInfo<T>`, `AuthState<T>`, `InvalidGrant`, `Transient`.
- Produces (exact public surface of `TokenManager<T>`):

```dart
class TokenManager<T> {
  @Deprecated('Use TokenManager.create.')
  TokenManager({
    required TokenStorage<T> storage,
    TokenManagerRefreshDelegate<T>? refreshDelegate,
    TokenInfoDelegate<T>? infoDelegate,
  });
  TokenManager.create({
    required TokenStore<T> store,
    TokenRefresher<T>? refresher,
    TokenInfo<T>? info,
    Duration skew = const Duration(seconds: 30),
    Clock clock = const Clock(),
  });

  Stream<AuthState<T>> get states;
  Future<T?> current();
  Future<T> validToken({T? rejected});
  Future<void> setTokens(T? tokens);          // null logs out
  Future<void> logout();
  Future<R> authorize<R>(Future<R> Function(T tokens) send, {required bool Function(Object error) isAuthFailure});
  Stream<R> authorizeStream<R>(Stream<R> Function(T tokens) open, {required bool Function(Object error) isAuthFailure});
  Future<void> dispose();

  // Deprecated, behaviour as before except where the CHANGELOG says so:
  T? get tokens;  Stream<T?> get tokensStream;  Future<void> initialize();
  Future<void> executeRefresh();  Future<void>? get waitForFresh;
}
```

Also `@Deprecated typedef TokenInfoDelegate<T> = TokenInfo<T>;`, `@Deprecated` on `TokenStorage`, `TokenManagerRefreshDelegate` and `RevokedTokensException`.

Behaviour of the deprecated members: `tokens` is the synchronous latest tokens (null before `initialize()` or `current()`); `tokensStream` replays the latest tokens, `null` meaning signed out; `executeRefresh()` forces a refresh and never throws (failures are swallowed as before); `waitForFresh` is null when idle; `setTokens(null)` logs out; a delegate throwing `RevokedTokensException` becomes `InvalidGrant` (logout), any other exception becomes `Transient`; no delegate means no refresh is ever attempted; `refreshThreshold` becomes the skew (default 3 minutes); `refreshDelay` is ignored.

- [ ] **Step 1: Move `RevokedTokensException` and deprecate the old types**

Create `lib/src/revoked_tokens_exception.dart`:

```dart
/// Exception thrown when tokens have been revoked and are no longer valid.
@Deprecated('Throw InvalidGrant from a TokenRefresher instead.')
class RevokedTokensException implements Exception {
  /// Creates a revoked-tokens exception.
  const RevokedTokensException();
}
```

Delete the `RevokedTokensException` class from the old `lib/src/token_manager.dart` content (the whole file is rewritten in Step 5). Add `@Deprecated('Use TokenStore, which has read, write and delete.')` immediately above `abstract interface class TokenStorage<T>` in `lib/src/token_storage.dart`, and `@Deprecated('Use TokenRefresher; set the expiry margin with TokenManager.create(skew: ...).')` above `abstract class TokenManagerRefreshDelegate<T>` in `lib/src/token_manager_refresh_delegate.dart` (it references `RevokedTokensException` and `TokenManager` in docs: keep the doc references valid). Replace the body of `lib/src/token_info_delegate.dart` with:

```dart
import 'token_info.dart';

/// Supplies metadata required to schedule proactive token refresh.
@Deprecated('Use TokenInfo.')
typedef TokenInfoDelegate<T> = TokenInfo<T>;
```

Files that mention the deprecated types need `// ignore_for_file: deprecated_member_use_from_same_package` with a reason comment on the line above, for example:

```dart
// The legacy adapters implement the deprecated API on purpose.
// ignore_for_file: deprecated_member_use_from_same_package
```

Add exactly that pair to the two adapter files and to `lib/src/token_manager.dart` below; do not add it anywhere the analyzer does not ask for it (`unnecessary_ignore` is on).

- [ ] **Step 2: Write the legacy adapters**

`lib/src/legacy/storage_token_store.dart`:

```dart
// The legacy adapters implement the deprecated API on purpose.
// ignore_for_file: deprecated_member_use_from_same_package

import '../token_storage.dart';
import '../token_store.dart';

/// Adapts the old [TokenStorage] to a [TokenStore].
final class StorageTokenStore<T> implements TokenStore<T> {
  /// Creates a store over [storage].
  const StorageTokenStore(this._storage);

  final TokenStorage<T> _storage;

  @override
  Future<T?> read() async => _storage.getTokens();

  @override
  Future<void> write(T tokens) => _storage.setTokens(tokens);

  @override
  Future<void> delete() => _storage.setTokens(null);
}
```

`lib/src/legacy/delegate_token_refresher.dart`:

```dart
// The legacy adapters implement the deprecated API on purpose.
// ignore_for_file: deprecated_member_use_from_same_package

import '../refresh_failure.dart';
import '../revoked_tokens_exception.dart';
import '../token_manager_refresh_delegate.dart';
import '../token_refresher.dart';

/// Adapts the old refresh delegate to a [TokenRefresher].
final class DelegateTokenRefresher<T> implements TokenRefresher<T> {
  /// Creates a refresher over [delegate].
  const DelegateTokenRefresher(this._delegate);

  final TokenManagerRefreshDelegate<T> _delegate;

  @override
  Future<T> refresh(T current) async {
    try {
      return await _delegate.refresh(current);
    } on RevokedTokensException {
      throw const InvalidGrant();
    }
  }
}
```

- [ ] **Step 3: Write the failing tests for the new surface**

`test/token_manager_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/fake_clock.dart';
import 'helpers/fake_refresher.dart';
import 'helpers/fake_token_store.dart';

final class _Unauthorized implements Exception {
  const _Unauthorized();
}

void main() {
  late FakeClock clock;
  late FakeTokenStore<TokenSet> store;
  late FakeRefresher<TokenSet> refresher;
  late TokenManager<TokenSet> manager;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  TokenSet tokens(Duration life, {String access = 'a'}) => TokenSet(
    accessToken: access,
    expiresAt: clock.now().add(life),
  );

  setUp(() {
    clock = FakeClock(DateTime.utc(2026));
    store = FakeTokenStore<TokenSet>();
    refresher = FakeRefresher<TokenSet>();
    manager = TokenManager<TokenSet>.create(
      store: store,
      refresher: refresher,
      info: const TokenSetInfo(),
      clock: clock,
    );
  });

  test('states replays Unauthenticated and then follows setTokens', () async {
    final seen = expectLater(
      manager.states,
      emitsInOrder([
        isA<Unauthenticated<TokenSet>>(),
        isA<Authenticated<TokenSet>>(),
      ]),
    );

    await manager.setTokens(tokens(const Duration(hours: 1)));

    await seen;
  });

  test('setTokens with null logs out', () async {
    await manager.setTokens(tokens(const Duration(hours: 1)));

    await manager.setTokens(null);

    expect(store.stored, isNull);
    expect(await manager.current(), isNull);
  });

  test('logout clears the session', () async {
    await manager.setTokens(tokens(const Duration(hours: 1)));

    await manager.logout();

    expect(await manager.current(), isNull);
  });

  test('authorize replays once with refreshed tokens', () async {
    final old = tokens(const Duration(hours: 1));
    await manager.setTokens(old);
    final sent = <TokenSet>[];

    final result = manager.authorize<String>((used) async {
      sent.add(used);
      if (identical(used, old)) {
        throw const _Unauthorized();
      }
      return 'ok';
    }, isAuthFailure: (error) => error is _Unauthorized);
    await settle();
    refresher.complete(tokens(const Duration(hours: 1), access: 'b'));

    expect(await result, 'ok');
    expect(sent, hasLength(2));
  });

  test('authorizeStream opens the source with valid tokens', () async {
    await manager.setTokens(tokens(const Duration(hours: 1), access: 'live'));

    final received = await manager
        .authorizeStream<String>(
          (used) => Stream.value(used.accessToken),
          isAuthFailure: (error) => error is _Unauthorized,
        )
        .toList();

    expect(received, ['live']);
  });

  test('a manager without a refresher never refreshes', () async {
    final plain = TokenManager<TokenSet>.create(store: store, clock: clock);
    final expiring = tokens(const Duration(seconds: 1));
    await plain.setTokens(expiring);

    expect(await plain.validToken(), same(expiring));
  });
}
```

`test/legacy/token_manager_legacy_test.dart`:

```dart
// These tests exercise the deprecated API on purpose.
// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

final class _MemoryStorage implements TokenStorage<String> {
  _MemoryStorage([this.stored]);

  String? stored;
  final List<String?> writes = [];

  @override
  String? getTokens() => stored;

  @override
  Future<void> setTokens(String? tokens) async {
    stored = tokens;
    writes.add(tokens);
  }
}

final class _Delegate extends TokenManagerRefreshDelegate<String> {
  _Delegate();

  Completer<String>? pending;
  Object? failWith;
  int calls = 0;

  @override
  Future<String> refresh(String tokens) {
    calls++;
    final error = failWith;
    if (error != null) {
      return Future<String>.error(error);
    }
    return (pending = Completer<String>()).future;
  }
}

void main() {
  late _MemoryStorage storage;
  late _Delegate delegate;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  TokenManager<String> manager({bool withDelegate = true}) {
    return TokenManager<String>(
      storage: storage,
      refreshDelegate: withDelegate ? delegate : null,
    );
  }

  setUp(() {
    storage = _MemoryStorage();
    delegate = _Delegate();
  });

  test('tokens is null until initialize loads the stored tokens', () async {
    storage.stored = 'saved';
    final legacy = manager();
    expect(legacy.tokens, isNull);

    await legacy.initialize();

    expect(legacy.tokens, 'saved');
  });

  test('tokensStream starts with null and then follows the tokens', () async {
    final legacy = manager();
    final seen = expectLater(legacy.tokensStream, emitsInOrder([null, 'a']));

    await legacy.setTokens('a');

    await seen;
  });

  test('setTokens persists, and null clears the storage', () async {
    final legacy = manager();
    await legacy.initialize();

    await legacy.setTokens('a');
    await legacy.setTokens(null);

    expect(storage.writes, ['a', null]);
    expect(legacy.tokens, isNull);
  });

  test('executeRefresh replaces the tokens with the delegate result',
      () async {
    final legacy = manager();
    await legacy.setTokens('old');

    final refreshing = legacy.executeRefresh();
    await settle();
    delegate.pending!.complete('new');
    await refreshing;

    expect(legacy.tokens, 'new');
    expect(storage.stored, 'new');
  });

  test('RevokedTokensException from the delegate logs out', () async {
    delegate.failWith = const RevokedTokensException();
    final legacy = manager();
    await legacy.setTokens('old');

    await legacy.executeRefresh();

    expect(legacy.tokens, isNull);
    expect(storage.stored, isNull);
  });

  test('another exception from the delegate keeps the tokens', () async {
    delegate.failWith = Exception('offline');
    final legacy = manager();
    await legacy.setTokens('old');

    await legacy.executeRefresh();

    expect(legacy.tokens, 'old');
    expect(storage.stored, 'old');
  });

  test('without a delegate executeRefresh does nothing', () async {
    final legacy = manager(withDelegate: false);
    await legacy.setTokens('old');

    await legacy.executeRefresh();

    expect(delegate.calls, 0);
    expect(legacy.tokens, 'old');
  });

  test('waitForFresh is null when idle and completes after the refresh',
      () async {
    final legacy = manager();
    await legacy.setTokens('old');
    expect(legacy.waitForFresh, isNull);

    final refreshing = legacy.executeRefresh();
    await settle();
    final waiting = legacy.waitForFresh;
    expect(waiting, isNotNull);
    delegate.pending!.complete('new');
    await refreshing;
    await waiting;

    expect(legacy.waitForFresh, isNull);
  });

  test('a TokenInfoDelegate still drives proactive refresh', () async {
    final legacy = TokenManager<String>(
      storage: storage,
      refreshDelegate: delegate,
      infoDelegate: _AlreadyExpired(),
    );
    await legacy.setTokens('stale');

    final valid = legacy.validToken();
    await settle();
    delegate.pending!.complete('fresh');

    expect(await valid, 'fresh');
  });
}

final class _AlreadyExpired implements TokenInfoDelegate<String> {
  @override
  DateTime? expiresAt(String tokens) => DateTime.utc(2000);
}
```

- [ ] **Step 4: Run to see them fail**

Run: `cd packages/token_manager && dart test test/token_manager_test.dart test/legacy`
Expected: FAIL (the new members do not exist yet).

- [ ] **Step 5: Rewrite `lib/src/token_manager.dart`**

```dart
// The deprecated constructor and members use the legacy types on purpose.
// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'auth_state.dart';
import 'clock.dart';
import 'engine/authorized_call.dart';
import 'engine/relay_stream.dart';
import 'engine/token_engine.dart';
import 'legacy/delegate_token_refresher.dart';
import 'legacy/storage_token_store.dart';
import 'token_info.dart';
import 'token_info_delegate.dart';
import 'token_manager_refresh_delegate.dart';
import 'token_refresher.dart';
import 'token_storage.dart';
import 'token_store.dart';

/// Manages the tokens of one session: storage, single-flight refresh and an
/// observable state.
class TokenManager<T> {
  /// Creates a manager from the old storage and delegates.
  @Deprecated('Use TokenManager.create.')
  TokenManager({
    required TokenStorage<T> storage,
    TokenManagerRefreshDelegate<T>? refreshDelegate,
    TokenInfoDelegate<T>? infoDelegate,
  }) : _engine = TokenEngine<T>(
         store: StorageTokenStore<T>(storage),
         skew: refreshDelegate?.refreshThreshold ?? const Duration(minutes: 3),
         clock: const Clock(),
         refresher: refreshDelegate == null
             ? null
             : DelegateTokenRefresher<T>(refreshDelegate),
         info: infoDelegate,
       );

  /// Creates a manager over [store].
  ///
  /// Tokens are refreshed with [refresher] when [info] says they expire within
  /// [skew], or when a server rejects them. Without a [refresher] tokens are
  /// never refreshed; without [info] they never expire.
  TokenManager.create({
    required TokenStore<T> store,
    TokenRefresher<T>? refresher,
    TokenInfo<T>? info,
    Duration skew = const Duration(seconds: 30),
    Clock clock = const Clock(),
  }) : _engine = TokenEngine<T>(
         store: store,
         skew: skew,
         clock: clock,
         refresher: refresher,
         info: info,
       );

  final TokenEngine<T> _engine;

  /// Emits the current state on listen, then every change.
  Stream<AuthState<T>> get states => _engine.states;

  /// Returns the current tokens without refreshing them.
  Future<T?> current() => _engine.current();

  /// Returns tokens that are valid now, refreshing them when needed.
  ///
  /// Pass the tokens a server just rejected as [rejected]. Concurrent callers
  /// share one refresh. Throws `NotAuthenticated` without tokens, `InvalidGrant`
  /// when the session ended, and `Transient` when the refresh may be retried.
  Future<T> validToken({T? rejected}) => _engine.validToken(rejected: rejected);

  /// Stores [tokens]; `null` signs out like [logout].
  Future<void> setTokens(T? tokens) =>
      tokens == null ? _engine.logout() : _engine.setTokens(tokens);

  /// Removes the tokens and signs the session out.
  Future<void> logout() => _engine.logout();

  /// Runs [send] with valid tokens, replaying it once after an auth failure.
  Future<R> authorize<R>(
    Future<R> Function(T tokens) send, {
    required bool Function(Object error) isAuthFailure,
  }) => AuthorizedCall<T>(_engine).run<R>(send, isAuthFailure: isAuthFailure);

  /// Opens a stream with valid tokens, reopening it once after an early auth
  /// failure. Pause, resume and cancel reach the source stream.
  Stream<R> authorizeStream<R>(
    Stream<R> Function(T tokens) open, {
    required bool Function(Object error) isAuthFailure,
  }) {
    return RelayStream<T, R>(
      acquire: validToken,
      renew: (rejected) => validToken(rejected: rejected),
      open: open,
      isAuthFailure: isAuthFailure,
    ).stream;
  }

  /// Releases the manager; work that finishes later is discarded.
  Future<void> dispose() => _engine.dispose();

  /// Returns the latest tokens, or `null` before they are loaded.
  @Deprecated('Use current() or states.')
  T? get tokens => _engine.state.tokensOrNull;

  /// Emits the tokens on every change; `null` means signed out.
  @Deprecated('Use states.')
  Stream<T?> get tokensStream =>
      _engine.states.map((state) => state.tokensOrNull);

  /// Loads the stored tokens.
  @Deprecated('Loading is lazy; use current().')
  Future<void> initialize() async {
    await _engine.current();
  }

  /// Forces a refresh; failures are swallowed.
  @Deprecated('Use validToken(rejected: ...).')
  Future<void> executeRefresh() async {
    final tokens = await _engine.current();
    if (tokens == null) {
      return;
    }
    try {
      await _engine.validToken(rejected: tokens);
    } on Exception catch (_) {
      // The old API never threw from a refresh; failures show in the state.
    }
  }

  /// Completes when the refresh in flight ends; `null` when none is running.
  @Deprecated('Use validToken().')
  Future<void>? get waitForFresh => _engine.pendingRefresh;
}
```

- [ ] **Step 6: Drop `rxdart`, the legacy store and the old example**

```bash
git rm lib/src/legacy_token_store.dart
```

In `pubspec.yaml` remove the whole `dependencies:` block (the core now has none; the `dev_dependencies:` block stays).

Replace `example/main.dart` with:

```dart
import 'dart:io';

import 'package:token_manager/token_manager.dart';

final class _ExampleRefresher implements TokenRefresher<TokenSet> {
  const _ExampleRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    return TokenSet(
      accessToken: 'new-access-token',
      refreshToken: 'new-refresh-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: const _ExampleRefresher(),
    info: const TokenSetInfo(),
  );

  // These tokens expire inside the default 30 second skew, so the next call
  // to validToken() refreshes them.
  await manager.setTokens(
    TokenSet(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().add(const Duration(seconds: 10)),
    ),
  );

  final tokens = await manager.validToken();
  stdout.writeln('Using access token: ${tokens.accessToken}');

  await manager.dispose();
}
```

- [ ] **Step 7: Update the barrel**

Replace `lib/token_manager.dart` with (keep sorted; reorder if an ordering lint complains):

```dart
/// Token lifecycle management: storage, single-flight refresh and an
/// observable session state.
library;

export 'src/auth_state.dart'
    show Authenticated, AuthState, Refreshing, Unauthenticated;
export 'src/clock.dart' show Clock;
export 'src/in_memory_token_store.dart' show InMemoryTokenStore;
export 'src/not_authenticated.dart' show NotAuthenticated;
export 'src/refresh_failure.dart' show InvalidGrant, RefreshFailure, Transient;
export 'src/revoked_tokens_exception.dart' show RevokedTokensException;
export 'src/token_info.dart' show TokenInfo;
export 'src/token_info_delegate.dart' show TokenInfoDelegate;
export 'src/token_manager.dart' show TokenManager;
export 'src/token_manager_refresh_delegate.dart'
    show TokenManagerRefreshDelegate;
export 'src/token_refresher.dart' show TokenRefresher;
export 'src/token_set.dart' show TokenSet;
export 'src/token_set_info.dart' show TokenSetInfo;
export 'src/token_storage.dart' show TokenStorage;
export 'src/token_store.dart' show TokenStore;
```

- [ ] **Step 8: Run the core tests**

Run: `dart pub get && dart test`
Expected: the whole `token_manager` suite passes.

- [ ] **Step 9: Keep the adapters compiling and the gate green**

Run: `cd ../.. && dart pub get && dart analyze packages 2>&1 | tail -n 40`

The dio and grpc packages still use the old API, so they report `deprecated_member_use` infos (and possibly nothing else). For **each** file under `packages/token_manager_dio/lib` and `packages/token_manager_grpc/lib` that the analyzer lists, add these two lines at the very top of the file:

```dart
// Uses the deprecated token_manager API until this adapter is rewritten (plan 2).
// ignore_for_file: deprecated_member_use
```

Do not add them to files without findings. Any finding other than `deprecated_member_use` in those packages means a real break: fix the call site to compile against the unchanged old signatures (they are all preserved) or stop and report.

Then run: `dart format packages && dart analyze packages && dart format --output=none --set-exit-if-changed packages && (cd packages/token_manager && dart test)`
Expected: `No issues found!`, exit 0, all tests pass.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat(token_manager): add the layered API and keep the old one as a facade

TokenManager gains create, states, current, validToken, logout, authorize
and authorizeStream on top of the token engine. The old constructor and
members are deprecated and behave as before except where the changelog
says otherwise. rxdart is removed.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 12: TokenManagerRegistry

**Files (relative to `packages/token_manager/`):**
- Create: `lib/src/token_manager_registry.dart`, `test/token_manager_registry_test.dart`
- Modify: `lib/token_manager.dart`

**Interfaces:**
- Consumes: `TokenManager<T>`, `TokenManager.create`, `InMemoryTokenStore<T>` (Task 11).
- Produces:

```dart
final class TokenManagerRegistry {
  TokenManagerRegistry();
  Iterable<String> get ids;
  void register<T>(String id, TokenManager<T> manager); // StateError on a duplicate id
  TokenManager<T> get<T>(String id);                      // StateError when missing or of another token type
  Future<void> dispose();                                 // disposes every manager and clears the registry
}
```

- [ ] **Step 1: Write the failing tests**

`test/token_manager_registry_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

void main() {
  late TokenManagerRegistry registry;

  TokenManager<String> stringManager() =>
      TokenManager<String>.create(store: InMemoryTokenStore<String>());

  setUp(() => registry = TokenManagerRegistry());

  test('returns the manager registered under an id', () {
    final manager = stringManager();

    registry.register<String>('main', manager);

    expect(registry.get<String>('main'), same(manager));
    expect(registry.ids, ['main']);
  });

  test('keeps providers with different token types apart', () {
    final strings = stringManager();
    final sets = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(),
    );

    registry
      ..register<String>('legacy', strings)
      ..register<TokenSet>('modern', sets);

    expect(registry.get<String>('legacy'), same(strings));
    expect(registry.get<TokenSet>('modern'), same(sets));
  });

  test('rejects a second manager for the same id', () {
    registry.register<String>('main', stringManager());

    expect(
      () => registry.register<String>('main', stringManager()),
      throwsStateError,
    );
  });

  test('rejects an unknown id', () {
    expect(() => registry.get<String>('missing'), throwsStateError);
  });

  test('rejects a request for the wrong token type', () {
    registry.register<String>('main', stringManager());

    expect(() => registry.get<TokenSet>('main'), throwsStateError);
  });

  test('dispose disposes every manager and empties the registry', () async {
    final manager = stringManager();
    registry.register<String>('main', manager);

    await registry.dispose();

    await expectLater(
      manager.states,
      emitsInOrder([isA<Unauthenticated<String>>(), emitsDone]),
    );
    expect(registry.ids, isEmpty);
  });
}
```

- [ ] **Step 2: Run to see it fail**

Run: `cd packages/token_manager && dart test test/token_manager_registry_test.dart`
Expected: FAIL (`TokenManagerRegistry` is not defined).

- [ ] **Step 3: Implement**

`lib/src/token_manager_registry.dart`:

```dart
import 'token_manager.dart';

/// Holds one [TokenManager] per provider id, each with its own token type.
final class TokenManagerRegistry {
  /// Creates an empty registry.
  TokenManagerRegistry();

  final Map<String, TokenManager<Object?>> _managers = {};

  /// The ids of the registered managers.
  Iterable<String> get ids => _managers.keys;

  /// Registers [manager] under [id].
  ///
  /// Throws a [StateError] when [id] is already taken.
  void register<T>(String id, TokenManager<T> manager) {
    if (_managers.containsKey(id)) {
      throw StateError('A token manager is already registered for "$id".');
    }
    _managers[id] = manager;
  }

  /// Returns the manager registered under [id].
  ///
  /// Throws a [StateError] when there is none, or when it handles another
  /// token type than [T].
  TokenManager<T> get<T>(String id) {
    final manager = _managers[id];
    if (manager == null) {
      throw StateError('No token manager is registered for "$id".');
    }
    if (manager is! TokenManager<T>) {
      throw StateError(
        'The token manager for "$id" has a different token type than $T.',
      );
    }
    return manager;
  }

  /// Disposes every manager and empties the registry.
  Future<void> dispose() async {
    for (final manager in _managers.values) {
      await manager.dispose();
    }
    _managers.clear();
  }
}
```

- [ ] **Step 4: Export it**

Add to `lib/token_manager.dart` (sorted, after `token_manager_refresh_delegate.dart`):

```dart
export 'src/token_manager_registry.dart' show TokenManagerRegistry;
```

- [ ] **Step 5: Run tests and the gate**

Run: `dart test && cd ../.. && dart format packages && dart analyze packages && dart format --output=none --set-exit-if-changed packages`
Expected: all pass; `No issues found!`; exit 0.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(token_manager): add TokenManagerRegistry for several providers

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Documentation: README, CHANGELOG and migration guide

**Files (relative to `packages/token_manager/`):**
- Rewrite: `README.md`
- Modify: `CHANGELOG.md`
- Create: `doc/migration.md`

**Interfaces:**
- Consumes: the public API from Tasks 6-12.
- Produces: user-facing docs that match the code.

- [ ] **Step 1: Replace `README.md`**

````markdown
# token_manager

Token lifecycle management for Dart: storage, single-flight refresh and an
observable session state. The core has no dependencies and knows nothing about
HTTP; transport packages (`token_manager_dio`, `token_manager_grpc`) plug into
it.

## Quick start

```dart
import 'package:token_manager/token_manager.dart';

final manager = TokenManager<TokenSet>.create(
  store: InMemoryTokenStore<TokenSet>(), // or a persistent TokenStore
  refresher: MyRefresher(), // implements TokenRefresher<TokenSet>
  info: const TokenSetInfo(),
);

await manager.setTokens(
  TokenSet(accessToken: 'access', refreshToken: 'refresh', expiresAt: expiry),
);

final tokens = await manager.validToken(); // refreshes when about to expire
```

`TokenSet` is a ready-made token value; use your own type `T` by implementing
`TokenStore<T>`, `TokenRefresher<T>` and `TokenInfo<T>`.

## Concepts

- **`validToken({rejected})`** returns tokens that are valid now. Concurrent
  callers share one refresh. Pass the tokens a server just rejected as
  `rejected`: they are refreshed unless another caller already replaced them.
- **Typed failures.** A `TokenRefresher` throws `InvalidGrant` when the refresh
  token was rejected for good (the session ends and `states` emits
  `Unauthenticated`) or `Transient` when the failure may go away (the session
  stays). Any other exception is treated as transient.
- **`states`** is a stream that replays the latest `AuthState` to each
  listener: `Unauthenticated`, `Authenticated` or `Refreshing`.
- **`authorize`** runs a call with valid tokens and replays it once after an
  auth failure. **`authorizeStream`** does the same for streams without
  `await for`, so pause, resume and cancel reach the source.
- **`TokenManagerRegistry`** keeps one manager per provider id.

## Migrating from 0.1

See [doc/migration.md](doc/migration.md).
````

- [ ] **Step 2: Add the changelog entry**

Insert at the top of `CHANGELOG.md`, above `## 0.1.0 - 2026-03-27`:

```markdown
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
- Tokens loaded from storage were never scheduled for refresh.
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
- `refreshDelay` is ignored: there is no retry timer. A transient failure is
  retried by the next call to `validToken`.
- `initialize()` is a lazy load and is no longer required.
- A failed refresh no longer ends in a hang: `InvalidGrant` signs out and any
  other failure keeps the session.
```

- [ ] **Step 3: Create `doc/migration.md`**

````markdown
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

- `refreshDelay` is ignored. There is no retry timer; a transient failure is
  retried by the next call to `validToken`.
- A refresher should throw `InvalidGrant` only when the refresh token was
  rejected for good. Everything else keeps the session.
- The minimum SDK is 3.10.
````

- [ ] **Step 4: Gate**

Run: `cd ../.. && dart format --output=none --set-exit-if-changed packages && dart analyze packages && (cd packages/token_manager && dart test)`
Expected: exit 0, `No issues found!`, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "docs(token_manager): document the layered API and the migration

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage** (spec sections 4-9, phases 0-2):

| Spec item | Task |
|---|---|
| Workspace resolution, SDK 3.10 (section 8, phase 0) | 1 |
| Merged `analysis_options.yaml`, zero-findings gate | 2 |
| `CLAUDE.md`, `CONTRIBUTING.md` | 3 |
| Size ratchet test | 4 |
| `ci.yml` (format, analyze, tests on min SDK and stable) | 5 |
| `Clock`, `RefreshFailure`, `TokenStore`, `TokenRefresher`, `TokenInfo`, `InMemoryTokenStore`, test fakes | 6 |
| `AuthState`, `TokenSet`, replaying state stream | 7 |
| `validToken`, single-flight, compare-and-skip, `InvalidGrant`/`Transient`, races, `dispose`, no timers (deadlock bugs 1, 2, 3, 4, 5, 6 of the review) | 8 |
| `authorize` with one replay | 9 |
| `RelayStream` (no `await for`, pause/resume/cancel) | 10 |
| Public `TokenManager`, `authorizeStream`, deprecated facade, `rxdart` removed, typedefs, adapters | 11 |
| `TokenManagerRegistry` | 12 |
| `doc/migration.md`, `CHANGELOG`, README | 13 |

Not in this plan, by design: `publish.yml` and `publish-dry-run` (phase 5), adapters (plan 2), storage packages (plan 3), `ProactiveRefresher` (phase 6).

**Placeholders:** none.

**Type consistency:** `TokenEngine.validToken({T? rejected})`, `pendingRefresh`, `AuthorizedCall.run`, `RelayStream` constructor parameters, and the `TokenManager` surface are identical wherever they appear (Tasks 8-12). `EngineFixture.tokens(Duration, {String access})` and `engine({bool withRefresher})` are used the same way in Tasks 8 and 9.

**Spec adjustment recorded:** the old and new `TokenManager` classes share one name, so the spec (sections 5 and 7) was updated before this plan: the class is evolved in place, `TokenStorage` is adapted (its shape differs from `TokenStore`), `setTokens` accepts `T?`, and `refresher`/`info` are optional.
