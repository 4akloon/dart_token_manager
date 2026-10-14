# Agent Discoverability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A coding agent in a project that does not use the packages yet finds the five `token_manager` packages on pub.dev and GitHub, learns from the first screen whether to use them, and copies a recipe whose code is compiled and tested.

**Architecture:** Metadata (`description`, `topics`, `repository`) and a "Should I use this?" block make the packages findable and self-explaining. Nine recipe pages live in `doc/recipes/` of the package that owns the code; each page includes, verbatim, a compiled and tested file from `example/recipes/`. A new unpublished workspace package, `packages/docs_check`, tests the documents themselves (metadata, README block, includes, links, wording). `docs/recipes.md` and `llms.txt` index the recipes. This work changes metadata, documents and examples, never `lib/`.

**Tech Stack:** Dart 3.10 pub workspace, `package:test`, `package:yaml` (dev dependency of `docs_check` only), the existing `dio`, `http`, `grpc` and `gql_link` dependencies of the adapter packages, Markdown, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-14-agent-discoverability-design.md`

**Base:** `main` after `chore/patch-releases` is merged. Do not start before that merge: both branches edit the same CHANGELOGs and pubspecs, and the recipe in Task 4 pins behaviour of the engine that branch refactors. Work on a new branch off `main` (for example `docs/agent-discoverability`) and run git from the repository root.

**Running Dart commands.** `dart test` and `dart analyze` have been OOM-killed in this environment. Wrap every `dart` command as `systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 timeout 300 dart ...`, run the tests of one file or one package at a time, and prefer `dart analyze <path>` over `dart analyze packages` until the final task. The commands below are written without the wrapper for readability.

## Global Constraints

- Patch releases only: `token_manager` 0.2.1, `token_manager_dio` 0.2.1, `token_manager_grpc` 0.2.1, `token_manager_gql` 0.1.1, `token_manager_http` 0.1.1. Version bumps and CHANGELOG entries are made once, in the last task.
- No change under any `lib/`. No `**Breaking:**` entry.
- `description` is 60 to 180 characters, one sentence, opens with the verb and the transport. `topics` are at most five, lowercase, 2 to 32 characters, `a-z`, `0-9` and `-`, start with a letter, no `--`.
- The first sentence of each README repeats the problem in the words of the search queries; the "Should I use this?" block follows the install section and answers: use it when / you do not need it when / what it replaces / which package.
- No claims about named third-party packages; compare approaches, not products.
- Every recipe is one page with the complete code, the expected behaviour and a "common mistakes" list; its code lives in `example/recipes/<name>.dart` of its package and the page includes it verbatim. Recipes link to the guides instead of repeating reference text.
- Repository rules apply to examples and tests: no top-level functions except `main`; no `!`, no `dynamic`; `late` needs a comment saying why; `catch` has an `on` clause; relative imports inside a package; tests ship in the same commit as the code and need no network.
- `dart format packages` second run changes 0 files; `dart analyze packages` prints `No issues found!`; `dart doc --dry-run` 0 warnings; `dart pub publish --dry-run` in each package shows no warnings.
- Code, comments, docs and commit messages are in English. Conventional Commits with a package scope where one package changes. Commit messages end with the `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` trailer.

## Review Focus

Failure modes the spec implies that no single feature test would catch; each line names the test that pins it.

1. **An API change silently breaks a recipe.** A page shows code that no longer compiles after `lib/` changes. Expected: `dart analyze packages` and the recipe tests fail in CI. Pinned by the recipe test of every recipe (Tasks 3 to 7) and by the final analyze in Task 9.
2. **A relative link works on GitHub and breaks on pub.dev.** A README with `](../other_package)` or a recipe page with a relative link points nowhere on pub.dev, which rewrites README links only through the `repository` URL and never rewrites API-doc pages. Expected: READMEs link outside their package by absolute pub.dev URL, recipe pages and `llms.txt` use absolute URLs only. Pinned by `readme_test.dart` (Task 2), `recipe_pages_test.dart` (Task 3) and `links_test.dart` (Task 8); the `repository` form is pinned by `pubspec_metadata_test.dart` (Task 1).
3. **A pubspec that pub.dev rejects or parses wrongly.** A description over 180 characters, an invalid or sixth topic, or an unquoted `description:` that contains `: ` (invalid YAML). Expected: the test fails before `dart pub publish --dry-run` does. Pinned by `pubspec_metadata_test.dart` (Task 1).
4. **Text that makes a claim about a named third-party package.** "Better than X", "unlike Y". Expected: the docs compare approaches only. Pinned by the banned-wording tests in `readme_test.dart` (Task 2) and `recipe_pages_test.dart` (Task 3).
5. **The page and the file drift apart.** An edit to `example/recipes/x.dart` without the page, or a new example nobody links. Expected: the test names the page. Pinned by the verbatim-include, at-least-one-include and orphan-example tests in `recipe_pages_test.dart` (Task 3).

## Rulings made while planning

1. The link check is the new unpublished workspace member `packages/docs_check` (dev dependencies `test` and `yaml`). `packages/` is already covered by the format and analyze steps; one CI test step runs on `ubuntu-latest` / `stable` only, which avoids Windows path differences. It has no size ratchet; its files stay far below the limits. One bullet is added to `CLAUDE.md` under "Where things are".
2. The `repository` field becomes `https://github.com/4akloon/dart_token_manager/tree/main/packages/<package>`. pub.dev rewrites relative README links for a monorepo package only with that form (dart-lang/pub-dev issue 5068). READMEs: package-local relative links only, cross-package links are absolute pub.dev URLs. Recipe pages: absolute GitHub `blob/main` URLs only. `llms.txt`: absolute only; the checker maps the `blob/main` prefix to local files. `docs/recipes.md`: relative links.
3. Descriptions are double-quoted in YAML, because `Dart: ...` is invalid unquoted YAML.
4. The descriptions of `token_manager_gql` and `token_manager_http` are replaced: they read noun-first ("A gql_link Link that ..."), not verb and transport first.
5. The "Which package" table has five rows (the core and four adapters); the spec said four lines.
6. A page shows its code through `<!-- include: path -->` followed by a `dart` fence. A test enforces that the fence equals the file, so a page cannot drift. The assembly script (Task 3) is a convenience and is not committed.
7. Stand-ins (fake server, fake secret box) are public classes in the recipe file and are reused by its test. Each recipe has a `main()`, so `dart run example/recipes/<name>.dart` works.
8. The GraphQL recipe takes a `SocketLinkBuilder` typedef because `graphql` is not a dependency of the package; the page says where to plug in the real socket link.
9. Pages show no printed output: an output pasted from a run would be unverified text.
10. The second Dio recipe (Task 4) pins, as a test, that a refresh sent through the interceptor `Dio` waits for itself (a timeout after 300 ms). If the engine refactor of `chore/patch-releases` changes that behaviour, change the test and the sentence on the page together; do not delete either.
11. Every `late` in the new tests carries a comment, as `CLAUDE.md` requires.

## Files

| Path | Responsibility |
|---|---|
| `packages/docs_check/pubspec.yaml` | unpublished workspace member; `test`, `yaml` |
| `packages/docs_check/test/helpers/repository_docs.dart` | `RepositoryDocs`: where the READMEs, recipe pages, examples, `llms.txt` and the index are |
| `packages/docs_check/test/helpers/markdown_links.dart` | `MarkdownLinks`: link targets and heading anchors of a Markdown text |
| `packages/docs_check/test/helpers/recipe_includes.dart` | `RecipeIncludes`: the include-marker check |
| `packages/docs_check/test/helpers/link_checker.dart` | `LinkChecker`: resolves links into the repository |
| `packages/docs_check/test/helpers/banned_wording.dart` | `BannedWording`: finds comparisons with other packages |
| `packages/docs_check/test/*_test.dart` | `pubspec_metadata`, `readme`, `markdown_links`, `recipe_pages`, `link_checker`, `links` |
| `packages/*/example/recipes/*.dart` | nine compiled recipes |
| `packages/*/test/recipes/*_test.dart` | their tests |
| `packages/*/doc/recipes/*.md` | nine recipe pages |
| `docs/recipes.md`, `llms.txt` | the index and the file for agents |

---

### Task 1: Metadata and the docs_check package

**Files:**
- Create: `packages/docs_check/pubspec.yaml`, `packages/docs_check/test/helpers/repository_docs.dart`, `packages/docs_check/test/pubspec_metadata_test.dart`
- Modify: `pubspec.yaml` (workspace), `packages/token_manager/pubspec.yaml`, `packages/token_manager_dio/pubspec.yaml`, `packages/token_manager_http/pubspec.yaml`, `packages/token_manager_grpc/pubspec.yaml`, `packages/token_manager_gql/pubspec.yaml`, `.github/workflows/ci.yml`, `CLAUDE.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `RepositoryDocs()` with `root` (`Directory`), `llms`, `recipeIndex` (`File`), `packages`, `readmes` (the root README first), `recipePages`, `recipeExamples`, `checkedPages` (`List<File>`), `packageOf(File) -> Directory`, `relativePath(File) -> String`. The tests run with `packages/docs_check` as the working directory.

- [ ] **Step 1: Create the package and add it to the workspace**

Create `packages/docs_check/pubspec.yaml`:

```yaml
name: docs_check
description: Checks that the READMEs, recipe pages, llms.txt and pubspec metadata of the workspace stay correct.
publish_to: none

environment:
  sdk: ^3.10.0

resolution: workspace

dev_dependencies:
  test: ^1.31.0
  yaml: ^3.1.0
```

In the root `pubspec.yaml`, add `- packages/docs_check` as the first entry of `workspace:` (the list stays sorted):

```yaml
workspace:
  - packages/docs_check
  - packages/token_manager
  - packages/token_manager_dio
  - packages/token_manager_gql
  - packages/token_manager_grpc
  - packages/token_manager_http
```

Run: `dart pub get`
Expected: it resolves. (`pubspec.lock` is ignored by git.)

- [ ] **Step 2: Write `RepositoryDocs`**

Create `packages/docs_check/test/helpers/repository_docs.dart`:

```dart
import 'dart:io';

/// Locates the documents the checks read; the tests run in
/// `packages/docs_check`.
final class RepositoryDocs {
  /// Creates the locator for the repository that contains the working
  /// directory's `packages/` folder.
  RepositoryDocs() : root = Directory.current.parent.parent;

  /// The repository root.
  final Directory root;

  /// `llms.txt` at the repository root.
  File get llms => File('${root.path}/llms.txt');

  /// The recipe index, `docs/recipes.md`.
  File get recipeIndex => File('${root.path}/docs/recipes.md');

  /// The publishable packages (every package but this one).
  List<Directory> get packages {
    final directories =
        Directory('${root.path}/packages')
            .listSync()
            .whereType<Directory>()
            .where((dir) => !dir.path.endsWith('/docs_check'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return directories;
  }

  /// The README of every package and the root README.
  List<File> get readmes => [
    File('${root.path}/README.md'),
    for (final package in packages) File('${package.path}/README.md'),
  ];

  /// Every `doc/recipes/*.md` of every package.
  List<File> get recipePages => [
    for (final package in packages)
      ..._files('${package.path}/doc/recipes', '.md'),
  ];

  /// Every `example/recipes/*.dart` of every package.
  List<File> get recipeExamples => [
    for (final package in packages)
      ..._files('${package.path}/example/recipes', '.dart'),
  ];

  /// Every page whose links are checked.
  List<File> get checkedPages => [
    ...readmes,
    ...recipePages,
    recipeIndex,
    llms,
  ];

  /// The package directory that owns [file].
  Directory packageOf(File file) {
    var directory = file.absolute.parent;
    while (!File('${directory.path}/pubspec.yaml').existsSync()) {
      directory = directory.parent;
    }
    return directory;
  }

  /// The path of [file] from the repository root.
  String relativePath(File file) {
    return file.absolute.path.substring(root.absolute.path.length + 1);
  }

  List<File> _files(String directory, String extension) {
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      return const [];
    }
    return dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith(extension))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }
}
```

- [ ] **Step 3: Write the failing metadata test**

Create `packages/docs_check/test/pubspec_metadata_test.dart`:

```dart
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'helpers/repository_docs.dart';

void main() {
  final docs = RepositoryDocs();
  // pub.dev: topics are 2-32 characters, lowercase letters, digits and
  // hyphens, start with a letter, end with a letter or digit, no `--`.
  final topic = RegExp(r'^[a-z](?:[a-z0-9]|-(?!-))*[a-z0-9]$');

  Map<String, Object?> pubspecOf(Directory package) {
    final yaml = loadYaml(
      File('${package.path}/pubspec.yaml').readAsStringSync(),
    );
    return switch (yaml) {
      final YamlMap map => {
        for (final entry in map.entries) '${entry.key}': entry.value,
      },
      _ => throw const FormatException('pubspec.yaml is not a map'),
    };
  }

  for (final package in docs.packages) {
    final name = package.path.split('/').last;

    group(name, () {
      final pubspec = pubspecOf(package);

      test('description is one sentence of 60 to 180 characters', () {
        final description = '${pubspec['description']}';

        expect(description.length, inInclusiveRange(60, 180));
        expect(description, endsWith('.'));
      });

      test('topics are at most five valid pub.dev topics', () {
        final topics = switch (pubspec['topics']) {
          final YamlList list => list.map((item) => '$item').toList(),
          _ => <String>[],
        };

        expect(topics, isNotEmpty);
        expect(topics.length, lessThanOrEqualTo(5));
        expect(topics.toSet(), hasLength(topics.length));
        for (final item in topics) {
          expect(item.length, inInclusiveRange(2, 32), reason: item);
          expect(topic.hasMatch(item), isTrue, reason: item);
        }
      });

      test('repository names the package folder, so README links resolve', () {
        expect(
          pubspec['repository'],
          'https://github.com/4akloon/dart_token_manager/tree/main/packages/$name',
        );
      });
    });
  }
}
```

- [ ] **Step 4: Run it to see it fail**

Run: `cd packages/docs_check && dart test test/pubspec_metadata_test.dart`
Expected: FAIL with 8 failures: the `topics` test of `token_manager`, `token_manager_dio` and `token_manager_grpc` (no topics yet) and the `repository` test of all five packages.

- [ ] **Step 5: Write the metadata of the five packages**

In each `packages/<name>/pubspec.yaml` change three things: replace the `description:` line, replace the `repository:` line (leave `homepage:` as it is), and set the `topics:` block directly after `issue_tracker:`. `token_manager_http` and `token_manager_gql` already have a `topics:` block there: replace it. Keep every other line, including the comments. The descriptions are double-quoted because they contain `: `.

Current `description:` lines for reference, which you replace:

- `token_manager`: `Token lifecycle management with storage, refresh, and token streams.`
- `token_manager_dio`: `Dio interceptor for token injection, refresh, and automatic retry.`
- `token_manager_http`: `A package:http client that attaches token_manager tokens to requests and replays a request once after an auth failure.`
- `token_manager_grpc`: `gRPC interceptor for token injection, refresh, and retry.`
- `token_manager_gql`: `A gql_link Link that attaches token_manager tokens to GraphQL requests and replays once after an auth failure.`

New values (the lines must read exactly like this; the number in brackets is the description length):

`packages/token_manager/pubspec.yaml` (122 characters):

```yaml
description: "Single-flight OAuth/JWT token refresh for Dart: pluggable storage, an observable session state and typed refresh failures."
repository: https://github.com/4akloon/dart_token_manager/tree/main/packages/token_manager
topics:
  - authentication
  - oauth
  - jwt
  - refresh-token
  - token
```

`packages/token_manager_dio/pubspec.yaml` (114 characters):

```yaml
description: "Single-flight OAuth/JWT refresh for Dio: attaches the access token, refreshes once on 401 and replays the request."
repository: https://github.com/4akloon/dart_token_manager/tree/main/packages/token_manager_dio
topics:
  - dio
  - authentication
  - interceptor
  - oauth
  - refresh-token
```

`packages/token_manager_http/pubspec.yaml` (137 characters):

```yaml
description: "Single-flight OAuth/JWT refresh for package:http: a Client that attaches the access token, refreshes once on 401 and replays the request."
repository: https://github.com/4akloon/dart_token_manager/tree/main/packages/token_manager_http
topics:
  - http
  - authentication
  - oauth
  - refresh-token
  - jwt
```

`packages/token_manager_grpc/pubspec.yaml` (144 characters):

```yaml
description: "Single-flight OAuth/JWT refresh for gRPC: an interceptor that attaches the access token, refreshes once on UNAUTHENTICATED and replays the call."
repository: https://github.com/4akloon/dart_token_manager/tree/main/packages/token_manager_grpc
topics:
  - grpc
  - authentication
  - interceptor
  - oauth
  - refresh-token
```

`packages/token_manager_gql/pubspec.yaml` (147 characters):

```yaml
description: "Single-flight OAuth/JWT refresh for GraphQL: a gql_link Link that attaches the access token, refreshes once on a rejection and replays the request."
repository: https://github.com/4akloon/dart_token_manager/tree/main/packages/token_manager_gql
topics:
  - graphql
  - gql
  - authentication
  - oauth
  - refresh-token
```

The order of the keys in the file stays `name`, `description`, `version`, `repository`, `homepage`, `issue_tracker`, `topics`, then `environment`.

- [ ] **Step 6: Run the test to see it pass**

Run: `cd packages/docs_check && dart test test/pubspec_metadata_test.dart`
Expected: PASS, 15 tests (three per package).

- [ ] **Step 7: Add the CI step and the CLAUDE.md bullet**

In `.github/workflows/ci.yml`, insert after the `Test token_manager_http` step:

```yaml
      - name: Test docs_check
        if: matrix.sdk == 'stable' && matrix.os == 'ubuntu-latest'
        working-directory: packages/docs_check
        run: dart test
```

In `CLAUDE.md`, under "Where things are", add after the `test/` bullet:

```markdown
- `packages/docs_check`: not published. Its tests check the pubspec metadata,
  the README blocks, the recipe pages (their `<!-- include: path -->` code
  blocks equal the files in `example/recipes/`), `docs/recipes.md`, `llms.txt`
  and every link between them. Run `cd packages/docs_check && dart test`.
```

- [ ] **Step 8: Format, analyze, commit**

Run: `dart format packages && dart analyze packages`
Expected: `0 changed` and `No issues found!`.

```bash
git add pubspec.yaml packages/docs_check packages/*/pubspec.yaml .github/workflows/ci.yml CLAUDE.md
git commit -m "docs: write the pub.dev metadata of the five packages and check it" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

### Task 2: README: the first sentence and "Should I use this?"

**Files:**
- Create: `packages/docs_check/test/readme_test.dart`, `packages/docs_check/test/helpers/banned_wording.dart`
- Modify: the `README.md` of the five packages

**Interfaces:**
- Consumes: `RepositoryDocs` (Task 1): `root`, `packages`.
- Produces: `BannedWording()` with `offendersIn(String text) -> List<String>`, the comparing phrases found in a text (used again in Task 3).

- [ ] **Step 1: Write the banned-wording finder**

Create `packages/docs_check/test/helpers/banned_wording.dart`:

```dart
/// Finds wording that compares this project with other packages.
///
/// The docs compare approaches (a hand-written interceptor), never products:
/// a claim about a named third-party package cannot be verified here and goes
/// stale.
final class BannedWording {
  /// Creates the finder.
  const BannedWording();

  static final RegExp _comparison = RegExp(
    r'\b(?:better|faster|safer|simpler|cleaner) than\b|\bunlike\b|'
    r'\bcompared (?:to|with)\b|\balternatives? to\b|\bvs\.?(?=\s)',
    caseSensitive: false,
  );

  /// The comparing phrases in [text], in order.
  List<String> offendersIn(String text) {
    return [for (final match in _comparison.allMatches(text)) match[0] ?? ''];
  }
}
```

- [ ] **Step 2: Write the failing README test**

The test pins, for every package: the block sits after `## Install` and the table of contents lists it; the block has the four labels and links to all five packages on pub.dev; the first bold sentence contains the phrase an agent searches for; the block compares approaches, never products; and no README link starts with `](../` (pub.dev would resolve it against the repository URL).

Create `packages/docs_check/test/readme_test.dart`:

```dart
import 'dart:io';

import 'package:test/test.dart';

import 'helpers/banned_wording.dart';
import 'helpers/repository_docs.dart';

void main() {
  final docs = RepositoryDocs();
  const wording = BannedWording();
  // What a coding agent searches for: one phrase the first sentence of each
  // README must contain.
  const searchPhrase = {
    'token_manager': 'refresh token',
    'token_manager_dio': 'refresh token interceptor',
    'token_manager_http': 'bearer token authorization and refresh on 401',
    'token_manager_grpc': 'auth token interceptor',
    'token_manager_gql': 'auth token',
  };

  String readmeOf(String package) {
    return File(
      '${docs.root.path}/packages/$package/README.md',
    ).readAsStringSync();
  }

  String blockOf(String readme) {
    final start = readme.indexOf('\n## Should I use this?\n');
    if (start < 0) {
      return '';
    }
    return readme.substring(start, readme.indexOf('\n## ', start + 1));
  }

  for (final MapEntry(key: package, value: phrase) in searchPhrase.entries) {
    group(package, () {
      final readme = readmeOf(package);

      test('has the "Should I use this?" block after Install', () {
        expect(
          readme.indexOf('\n## Should I use this?\n'),
          greaterThan(readme.indexOf('\n## Install\n')),
        );
        expect(readme, contains('- [Should I use this?](#should-i-use-this)'));
      });

      test('the block answers use it, do not need it, replaces, which', () {
        final block = blockOf(readme);

        expect(block, contains('- **Use it when:**'));
        expect(block, contains('- **You do not need it when:**'));
        expect(block, contains('- **What it replaces:**'));
        expect(block, contains('- **Which package:**'));
        for (final other in searchPhrase.keys) {
          expect(block, contains('https://pub.dev/packages/$other)'));
        }
      });

      test('the first sentence uses the words of the search queries', () {
        final first = readme
            .split('\n')
            .firstWhere(
              (line) => line.startsWith('**'),
            );

        expect(first.toLowerCase(), contains(phrase));
      });

      test('compares approaches, never named products', () {
        expect(wording.offendersIn(blockOf(readme)), isEmpty);
      });

      test('links outside the package folder are absolute', () {
        expect(readme, isNot(contains('](../')));
      });
    });
  }
}
```

- [ ] **Step 3: Run it to see it fail**

Run: `cd packages/docs_check && dart test test/readme_test.dart`
Expected: FAIL: 25 tests, most of them fail (no block yet; `](../` still present in the dio and grpc READMEs).

- [ ] **Step 4: Edit the five READMEs**

Apply the edits below. Every `Replace` text occurs exactly once in the current README; if it does not, the README changed on `main` since this plan was written, so adapt the edit to the current wording and keep the result. The new first sentence is bold and carries the search phrase; the block is placed before `## Quick start`, which follows the install section; the table of contents gains the entry. The `](../` links of the dio and grpc READMEs become absolute pub.dev links.

In every block the "What it replaces" item names an approach (a hand-written interceptor, client wrapper or link), never another package.

**`packages/token_manager/README.md`**

Edit 1. Replace

```markdown
**The core of [dart_token_manager](../../README.md)** — storage, single-flight refresh and an observable
session state for authentication tokens. Pure Dart, no runtime dependencies, and it knows nothing about
HTTP: the transport adapters ([`token_manager_dio`](../token_manager_dio),
[`token_manager_grpc`](../token_manager_grpc)) plug into it.
```

with

```markdown
**Dart refresh token and OAuth/JWT session management without races** — `token_manager` stores the access
and refresh tokens, refreshes them once for any number of concurrent callers (single-flight) and exposes
the session as a stream. It is the core of [dart_token_manager](https://github.com/4akloon/dart_token_manager).
Pure Dart, no runtime dependencies, and it knows nothing about HTTP: the transport adapters
([`token_manager_dio`](https://pub.dev/packages/token_manager_dio),
[`token_manager_http`](https://pub.dev/packages/token_manager_http),
[`token_manager_grpc`](https://pub.dev/packages/token_manager_grpc),
[`token_manager_gql`](https://pub.dev/packages/token_manager_gql)) plug into it.
```

Edit 2. Replace

```markdown
- [Quick start](#quick-start)
```

with

```markdown
- [Should I use this?](#should-i-use-this)
- [Quick start](#quick-start)
```

Edit 3. Replace

```markdown

## Quick start
```

with

```markdown

## Should I use this?

- **Use it when:** the app has an access token and a refresh token, several requests can run at once, and a 401 must trigger exactly one refresh.
- **You do not need it when:** the API uses a long-lived static key, or the app never refreshes tokens.
- **What it replaces:** a hand-written refresh scattered over repositories and interceptors. That code tends to refresh once per failed request (N parallel 401s cause N refreshes) and to loop when the refresh itself fails. Here the manager keeps one refresh in flight, a request is replayed at most once, and a failed refresh reaches the caller as a typed error.
- **Which package:**

| You use | Package |
|---|---|
| Any Dart code, or a transport not listed here | [`token_manager`](https://pub.dev/packages/token_manager) (this package) |
| `dio` | [`token_manager_dio`](https://pub.dev/packages/token_manager_dio) |
| `package:http` | [`token_manager_http`](https://pub.dev/packages/token_manager_http) |
| `grpc` | [`token_manager_grpc`](https://pub.dev/packages/token_manager_grpc) |
| GraphQL (`gql_link`) | [`token_manager_gql`](https://pub.dev/packages/token_manager_gql) |

Every adapter needs the core, so install `token_manager` too.

## Quick start
```

**`packages/token_manager_dio/README.md`**

Edit 1. Replace

```markdown
**The [Dio](https://pub.dev/packages/dio) adapter for [`token_manager`](../token_manager)** — one
interceptor that attaches the access token, recognises an auth failure and replays the request once.
It depends only on the core and `dio`, and never refreshes by itself: the manager owns the refresh.
```

with

```markdown
**Dio refresh token interceptor: attach the bearer token, refresh once on 401 and retry the request** — the
[Dio](https://pub.dev/packages/dio) adapter for [`token_manager`](https://pub.dev/packages/token_manager).
One `DioTokenInterceptor` attaches the access token, recognises an auth failure and replays the request once.
It depends only on the core and `dio`, and never refreshes by itself: the manager owns the refresh.
```

Edit 2. Replace

```markdown
- [`token_manager`](../token_manager) — the core: storage, single-flight refresh, errors.
```

with

```markdown
- [`token_manager`](https://pub.dev/packages/token_manager) — the core: storage, single-flight refresh, errors.
```

Edit 3. Replace

```markdown
- [Quick start](#quick-start)
```

with

```markdown
- [Should I use this?](#should-i-use-this)
- [Quick start](#quick-start)
```

Edit 4. Replace

```markdown

## Quick start
```

with

```markdown

## Should I use this?

- **Use it when:** the app has an access token and a refresh token, several requests can run at once, and a 401 must trigger exactly one refresh.
- **You do not need it when:** the API uses a long-lived static key, or the app never refreshes tokens.
- **What it replaces:** a hand-written Dio interceptor that refreshes in `onError`. That code tends to refresh once per failed request (N parallel 401s cause N refreshes) and to loop when the refresh itself fails. Here the manager keeps one refresh in flight, a request is replayed at most once, and a failed refresh reaches the caller as a typed error.
- **Which package:**

| You use | Package |
|---|---|
| Any Dart code, or a transport not listed here | [`token_manager`](https://pub.dev/packages/token_manager) |
| `dio` | [`token_manager_dio`](https://pub.dev/packages/token_manager_dio) (this package) |
| `package:http` | [`token_manager_http`](https://pub.dev/packages/token_manager_http) |
| `grpc` | [`token_manager_grpc`](https://pub.dev/packages/token_manager_grpc) |
| GraphQL (`gql_link`) | [`token_manager_gql`](https://pub.dev/packages/token_manager_gql) |

Every adapter needs the core, so install `token_manager` too.

## Quick start
```

**`packages/token_manager_http/README.md`**

Edit 1. Replace

```markdown
**The `package:http` adapter for [`token_manager`](https://pub.dev/packages/token_manager)**: `HttpTokenClient`,
a `BaseClient` that wraps your `Client`, attaches the manager's tokens to every request and replays a request
once after the server rejects them. It depends only on `http` and `token_manager`.
```

with

```markdown
**An `http` client with bearer token authorization and refresh on 401** — the `package:http` adapter for
[`token_manager`](https://pub.dev/packages/token_manager): `HttpTokenClient`, a `BaseClient` that wraps your
`Client`, attaches the access token to every request, refreshes once when the server rejects it and replays
the request. It depends only on `http` and `token_manager`.
```

Edit 2. Replace

```markdown
- [Quick start](#quick-start)
```

with

```markdown
- [Should I use this?](#should-i-use-this)
- [Quick start](#quick-start)
```

Edit 3. Replace

```markdown

## Quick start
```

with

```markdown

## Should I use this?

- **Use it when:** the app has an access token and a refresh token, several requests can run at once, and a 401 must trigger exactly one refresh.
- **You do not need it when:** the API uses a long-lived static key, or the app never refreshes tokens.
- **What it replaces:** a hand-written `package:http` `Client` wrapper that adds the header and retries after a 401. That code tends to refresh once per failed request (N parallel 401s cause N refreshes) and to loop when the refresh itself fails. Here the manager keeps one refresh in flight, a request is replayed at most once, and a failed refresh reaches the caller as a typed error.
- **Which package:**

| You use | Package |
|---|---|
| Any Dart code, or a transport not listed here | [`token_manager`](https://pub.dev/packages/token_manager) |
| `dio` | [`token_manager_dio`](https://pub.dev/packages/token_manager_dio) |
| `package:http` | [`token_manager_http`](https://pub.dev/packages/token_manager_http) (this package) |
| `grpc` | [`token_manager_grpc`](https://pub.dev/packages/token_manager_grpc) |
| GraphQL (`gql_link`) | [`token_manager_gql`](https://pub.dev/packages/token_manager_gql) |

Every adapter needs the core, so install `token_manager` too.

## Quick start
```

**`packages/token_manager_grpc/README.md`**

Edit 1. Replace

```markdown
**gRPC client interceptor for [token_manager](../token_manager)** — attaches valid tokens to every
call and, when the server rejects them, refreshes once and replays the call once.
```

with

```markdown
**gRPC Dart auth token interceptor: attach the bearer token, refresh once on UNAUTHENTICATED and replay the
call** — the `package:grpc` adapter for [token_manager](https://pub.dev/packages/token_manager). It attaches
valid tokens to every call and, when the server rejects them, refreshes once and replays the call once.
```

Edit 2. Replace

```markdown
- Core package: [token_manager](../token_manager)
```

with

```markdown
- Core package: [token_manager](https://pub.dev/packages/token_manager)
```

Edit 3. Replace

```markdown
- [Quick start](#quick-start)
```

with

```markdown
- [Should I use this?](#should-i-use-this)
- [Quick start](#quick-start)
```

Edit 4. Replace

```markdown

## Quick start
```

with

```markdown

## Should I use this?

- **Use it when:** the app has an access token and a refresh token, several requests can run at once, and a 401 must trigger exactly one refresh.
- **You do not need it when:** the API uses a long-lived static key, or the app never refreshes tokens.
- **What it replaces:** a hand-written gRPC `ClientInterceptor` that refreshes when a call fails. That code tends to refresh once per failed request (N parallel 401s cause N refreshes) and to loop when the refresh itself fails. Here the manager keeps one refresh in flight, a request is replayed at most once, and a failed refresh reaches the caller as a typed error.
- **Which package:**

| You use | Package |
|---|---|
| Any Dart code, or a transport not listed here | [`token_manager`](https://pub.dev/packages/token_manager) |
| `dio` | [`token_manager_dio`](https://pub.dev/packages/token_manager_dio) |
| `package:http` | [`token_manager_http`](https://pub.dev/packages/token_manager_http) |
| `grpc` | [`token_manager_grpc`](https://pub.dev/packages/token_manager_grpc) (this package) |
| GraphQL (`gql_link`) | [`token_manager_gql`](https://pub.dev/packages/token_manager_gql) |

Every adapter needs the core, so install `token_manager` too.

## Quick start
```

**`packages/token_manager_gql/README.md`**

Edit 1. Replace

```markdown
**The GraphQL adapter for [`token_manager`](https://pub.dev/packages/token_manager)** — a
[`gql_link`](https://pub.dev/packages/gql_link) `Link` that attaches the manager's tokens to every request
and replays a request once after the server rejects them. It works with every client built on `gql_link`
```

with

```markdown
**GraphQL auth token for Dart: a `gql_link` `Link` that adds the bearer token, refreshes once on a rejection
and replays the request** — the GraphQL adapter for [`token_manager`](https://pub.dev/packages/token_manager),
built on [`gql_link`](https://pub.dev/packages/gql_link). It works with every client built on `gql_link`
```

Edit 2. Replace

```markdown
- [Quick start](#quick-start)
```

with

```markdown
- [Should I use this?](#should-i-use-this)
- [Quick start](#quick-start)
```

Edit 3. Replace

```markdown

## Quick start
```

with

```markdown

## Should I use this?

- **Use it when:** the app has an access token and a refresh token, several requests can run at once, and a 401 must trigger exactly one refresh.
- **You do not need it when:** the API uses a long-lived static key, or the app never refreshes tokens.
- **What it replaces:** a hand-written GraphQL `Link` that adds the header and retries after an auth error. That code tends to refresh once per failed request (N parallel 401s cause N refreshes) and to loop when the refresh itself fails. Here the manager keeps one refresh in flight, a request is replayed at most once, and a failed refresh reaches the caller as a typed error.
- **Which package:**

| You use | Package |
|---|---|
| Any Dart code, or a transport not listed here | [`token_manager`](https://pub.dev/packages/token_manager) |
| `dio` | [`token_manager_dio`](https://pub.dev/packages/token_manager_dio) |
| `package:http` | [`token_manager_http`](https://pub.dev/packages/token_manager_http) |
| `grpc` | [`token_manager_grpc`](https://pub.dev/packages/token_manager_grpc) |
| GraphQL (`gql_link`) | [`token_manager_gql`](https://pub.dev/packages/token_manager_gql) (this package) |

Every adapter needs the core, so install `token_manager` too.

## Quick start
```

- [ ] **Step 5: Run the test to see it pass**

Run: `cd packages/docs_check && dart test test/readme_test.dart`
Expected: PASS, 25 tests.

Run: `cd packages/docs_check && dart test`
Expected: PASS (metadata and README tests).

- [ ] **Step 6: Format, analyze, commit**

Run: `dart format packages && dart analyze packages`
Expected: `0 changed` and `No issues found!`.

```bash
git add packages/docs_check packages/*/README.md
git commit -m "docs: add Should I use this? to the five READMEs" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

### Task 3: Recipe infrastructure and the four core recipes

**Files:**
- Create: `packages/docs_check/test/helpers/markdown_links.dart`, `packages/docs_check/test/helpers/recipe_includes.dart`, `packages/docs_check/test/markdown_links_test.dart`, `packages/docs_check/test/recipe_pages_test.dart`
- Create, for each of `login_and_set_tokens`, `secure_token_store`, `session_expiry`, `testing_without_network`: `packages/token_manager/example/recipes/<name>.dart`, `packages/token_manager/test/recipes/<name>_test.dart`, `packages/token_manager/doc/recipes/<name>.md`
- Modify: `packages/token_manager/README.md`

**Interfaces:**
- Consumes: `RepositoryDocs` (`recipePages`, `recipeExamples`, `packageOf`), `BannedWording.offendersIn` (Task 2).
- Produces: `MarkdownLinks()` with `targetsIn(String) -> List<String>` (link targets outside fenced and inline code), `anchorsIn(String) -> Set<String>` (heading anchors), `slug(String) -> String`; `RecipeIncludes()` with `includedBy(File page) -> List<String>` and `failuresIn(File page, Directory packageRoot) -> List<String>`. The recipe procedure used again by Tasks 4 to 7.

**The recipe procedure** (Tasks 3 to 7). A recipe is three files: `example/recipes/<name>.dart` (compiled by `dart analyze packages`, runnable with `dart run`), `test/recipes/<name>_test.dart` (no network) and `doc/recipes/<name>.md`. The page has a title `# Recipe: ...`, an introduction, `## The code` with one `<!-- include: example/recipes/<name>.dart -->` line that a `dart` block holding the file follows, `## What you get`, `## Common mistakes` and `## See also` with absolute GitHub `blob/main` links. Order inside a recipe: test, see it fail, example, see it pass, page, see the docs test pass, commit.

- [ ] **Step 1: Write the tests of the helpers**

Create `packages/docs_check/test/markdown_links_test.dart`:

````dart
import 'package:test/test.dart';

import 'helpers/markdown_links.dart';

void main() {
  const links = MarkdownLinks();

  test('targetsIn finds inline links with anchors', () {
    const text = 'See [a](doc/a.md#x) and [b](https://pub.dev/packages/b).';

    expect(links.targetsIn(text), ['doc/a.md#x', 'https://pub.dev/packages/b']);
  });

  test('targetsIn ignores fenced code and inline code', () {
    const text = '''
`[no](inline.md)`

```dart
// [no](fenced.md)
```

[yes](real.md)
''';

    expect(links.targetsIn(text), ['real.md']);
  });

  test('targetsIn ignores a link title', () {
    expect(links.targetsIn('[a](a.md "Title")'), ['a.md']);
  });

  test('slug follows the GitHub rule', () {
    expect(links.slug('Migrating from 0.1'), 'migrating-from-01');
    expect(links.slug('`TokenStore` and more'), 'tokenstore-and-more');
    expect(links.slug('Should I use this?'), 'should-i-use-this');
  });

  test('anchorsIn numbers a repeated heading', () {
    const text = '# One\n\n## Two\n\n## Two\n';

    expect(links.anchorsIn(text), {'one', 'two', 'two-1'});
  });

  test('anchorsIn skips a comment inside a fenced block', () {
    const text = '```sh\n# not a heading\n```\n\n# Real\n';

    expect(links.anchorsIn(text), {'real'});
  });
}
````

Create `packages/docs_check/test/recipe_pages_test.dart`. It pins review-focus items 2, 4 and 5: the page shows exactly the file, every page includes a file, every example is included, a page has no relative link and no banned comparison.

```dart
import 'dart:io';

import 'package:test/test.dart';

import 'helpers/banned_wording.dart';
import 'helpers/markdown_links.dart';
import 'helpers/recipe_includes.dart';
import 'helpers/repository_docs.dart';

void main() {
  final docs = RepositoryDocs();
  const links = MarkdownLinks();
  const includes = RecipeIncludes();
  const wording = BannedWording();

  test('every recipe page shows its code exactly as the compiled file', () {
    final failures = [
      for (final page in docs.recipePages)
        ...includes.failuresIn(page, docs.packageOf(page)),
    ];

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('every recipe page includes at least one file', () {
    final empty = [
      for (final page in docs.recipePages)
        if (includes.includedBy(page).isEmpty) page.path,
    ];

    expect(empty, isEmpty, reason: empty.join('\n'));
  });

  test('every recipe example is included by a page of its package', () {
    final included = {
      for (final page in docs.recipePages)
        for (final path in includes.includedBy(page))
          File.fromUri(docs.packageOf(page).uri.resolve(path)).absolute.path,
    };

    final orphans = [
      for (final example in docs.recipeExamples)
        if (!included.contains(example.absolute.path)) example.path,
    ];

    expect(orphans, isEmpty, reason: orphans.join('\n'));
  });

  test('a recipe page has no relative file link', () {
    // The API docs of pub.dev do not rewrite relative links, so a recipe page
    // links to other files by absolute URL.
    final offenders = [
      for (final page in docs.recipePages)
        for (final target in links.targetsIn(page.readAsStringSync()))
          if (!target.contains(':') && !target.startsWith('#'))
            '${page.path}: ($target)',
    ];

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('a recipe page compares approaches, never named products', () {
    final offenders = [
      for (final page in docs.recipePages)
        for (final phrase in wording.offendersIn(page.readAsStringSync()))
          '${page.path}: $phrase',
    ];

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd packages/docs_check && dart test test/markdown_links_test.dart test/recipe_pages_test.dart`
Expected: FAIL to compile: `helpers/markdown_links.dart` and `helpers/recipe_includes.dart` do not exist.

- [ ] **Step 3: Write the helpers**

Create `packages/docs_check/test/helpers/markdown_links.dart`:

````dart
/// Finds the links and the heading anchors of a Markdown text.
///
/// Fenced code blocks and inline code are ignored, so a link written as an
/// example in a recipe is not checked.
final class MarkdownLinks {
  /// Creates the reader.
  const MarkdownLinks();

  static final RegExp _fence = RegExp(r'^\s*(```|~~~)');
  static final RegExp _inlineCode = RegExp('`[^`]*`');
  static final RegExp _link = RegExp(r'\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)');
  static final RegExp _heading = RegExp(r'^#{1,6}\s+(.*?)\s*#*\s*$');
  static final RegExp _dropped = RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true);

  /// The targets of the inline links in [markdown], in order.
  List<String> targetsIn(String markdown) {
    final targets = <String>[];
    for (final line in _prose(markdown)) {
      for (final match in _link.allMatches(line)) {
        if (match.group(1) case final String target) {
          targets.add(target);
        }
      }
    }
    return targets;
  }

  /// The anchors GitHub generates for the headings of [markdown].
  Set<String> anchorsIn(String markdown) {
    final anchors = <String>{};
    final seen = <String, int>{};
    for (final line in _prose(markdown)) {
      final match = _heading.firstMatch(line);
      if (match?.group(1) case final String text) {
        final base = slug(text);
        final count = seen[base] ?? 0;
        seen[base] = count + 1;
        anchors.add(count == 0 ? base : '$base-$count');
      }
    }
    return anchors;
  }

  /// The GitHub anchor of the heading [text].
  String slug(String text) {
    return text
        .replaceAll('`', '')
        .toLowerCase()
        .replaceAll(_dropped, '')
        .trim()
        .replaceAll(' ', '-');
  }

  /// The lines outside fenced code blocks, without inline code.
  Iterable<String> _prose(String markdown) sync* {
    var isFenced = false;
    for (final line in markdown.split('\n')) {
      if (_fence.hasMatch(line)) {
        isFenced = !isFenced;
      } else if (!isFenced) {
        yield line.replaceAll(_inlineCode, '');
      }
    }
  }
}
````

Create `packages/docs_check/test/helpers/recipe_includes.dart`:

````dart
import 'dart:io';

/// Checks that a recipe page shows its code exactly as the compiled file.
///
/// A page marks an included file with a comment line, directly followed by a
/// `dart` fenced block that holds the file:
///
/// ```text
/// <!-- include: example/recipes/name.dart -->
/// ```
///
/// The path is relative to the package that owns the page.
final class RecipeIncludes {
  /// Creates the checker.
  const RecipeIncludes();

  static final RegExp _marker = RegExp(r'^<!-- include: (\S+) -->$');

  /// The paths [page] includes, relative to its package.
  List<String> includedBy(File page) {
    return [
      for (final line in page.readAsLinesSync())
        if (_marker.firstMatch(line)?.group(1) case final String path) path,
    ];
  }

  /// The includes of [page] that differ from their file, as messages.
  List<String> failuresIn(File page, Directory packageRoot) {
    final lines = page.readAsLinesSync();
    final failures = <String>[];
    for (var index = 0; index < lines.length; index++) {
      if (_marker.firstMatch(lines[index])?.group(1) case final String path) {
        final problem = _problemWith(path, lines, index + 1, packageRoot);
        if (problem != null) {
          failures.add('${page.path}: include $path $problem');
        }
      }
    }
    return failures;
  }

  String? _problemWith(
    String path,
    List<String> lines,
    int fenceIndex,
    Directory packageRoot,
  ) {
    final file = File.fromUri(packageRoot.absolute.uri.resolve(path));
    if (!file.existsSync()) {
      return 'names a file that does not exist';
    }
    if (fenceIndex >= lines.length || lines[fenceIndex] != '```dart') {
      return 'is not followed by a ```dart block';
    }
    final shown = <String>[];
    for (var i = fenceIndex + 1; i < lines.length && lines[i] != '```'; i++) {
      shown.add(lines[i]);
    }
    return shown.join('\n') == file.readAsStringSync().trimRight()
        ? null
        : 'differs from the file; paste the file again';
  }
}
````

- [ ] **Step 4: Run them to see them pass**

Run: `cd packages/docs_check && dart test test/markdown_links_test.dart test/recipe_pages_test.dart`
Expected: PASS (the page tests pass because there is no recipe page or example yet).

- [ ] **Step 5: Create the assembly script**

The pages hold a copy of the compiled file. To avoid pasting by hand, create `/tmp/assemble_recipe.py` (outside the repository; do not commit it). It expands every include marker of the pages it is given, and running it again refreshes the block:

````python
"""Expands the include markers of recipe pages (not committed)."""
import pathlib
import re
import sys

MARKER = re.compile(r'<!-- include: (\S+) -->')

for argument in sys.argv[1:]:
    page = pathlib.Path(argument)
    package = page.parent.parent.parent
    lines = page.read_text().split('\n')
    result = []
    index = 0
    while index < len(lines):
        line = lines[index]
        index += 1
        result.append(line)
        match = MARKER.fullmatch(line)
        if match is None:
            continue
        if index < len(lines) and lines[index] == '```dart':
            index += 1
            while lines[index] != '```':
                index += 1
            index += 1
        body = (package / match.group(1)).read_text().rstrip('\n')
        result += ['```dart', body, '```']
    page.write_text('\n'.join(result))
    print('assembled', page)
````

- [ ] **Step 6: Commit the helpers**

Run: `dart format packages && dart analyze packages/docs_check`
Expected: `0 changed` and `No issues found!`.

```bash
git add packages/docs_check
git commit -m "test: add the markdown link and recipe include checks to docs_check" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Now the four recipes. Each one ends with its own commit.

#### Recipe `login_and_set_tokens` (Sign in and store the tokens)

Public names of the example (the test and the page use them): `TokenResponse`, `TokenResponseTokens`, `GrantRejected`, `AuthApi`, `ApiRefresher`, `Session`, `StandInAuthServer`.

- [ ] **Step 7: Write the test of `login_and_set_tokens`**

Create `packages/token_manager/test/recipes/login_and_set_tokens_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/login_and_set_tokens.dart'
    show GrantRejected, Session, StandInAuthServer;

void main() {
  // Assigned in setUp, which runs before every test.
  late StandInAuthServer server;
  late Session session;

  setUp(() {
    server = StandInAuthServer();
    session = Session(api: server);
  });

  tearDown(() => session.dispose());

  test('signIn stores the tokens', () async {
    await session.signIn('ada@example.com', 'secret');

    final tokens = await session.manager.current();
    expect(tokens?.accessToken, 'access-1');
    expect(tokens?.expiresAt, isNotNull);
  });

  test('bad credentials leave the session signed out', () async {
    await expectLater(
      session.signIn('ada@example.com', 'wrong'),
      throwsA(isA<GrantRejected>()),
    );

    expect(await session.manager.current(), isNull);
  });

  test('signOut removes the tokens', () async {
    await session.signIn('ada@example.com', 'secret');

    await session.signOut();

    expect(await session.manager.current(), isNull);
  });

  test('expired tokens are refreshed once on the next validToken', () async {
    server = StandInAuthServer(lifetime: const Duration(seconds: 5));
    session = Session(api: server);
    await session.signIn('ada@example.com', 'secret');

    final tokens = await session.manager.validToken();

    expect(tokens.accessToken, 'access-2');
    expect(server.refreshes, 1);
  });

  test('a rejected refresh token signs the session out', () async {
    server = StandInAuthServer(lifetime: const Duration(seconds: 5));
    session = Session(api: server);
    await session.signIn('ada@example.com', 'secret');
    server.isRevoked = true;

    await expectLater(
      session.manager.validToken(),
      throwsA(isA<InvalidGrant>()),
    );

    expect(await session.manager.current(), isNull);
  });

  test('a network error keeps the session', () async {
    server = StandInAuthServer(lifetime: const Duration(seconds: 5));
    session = Session(api: server);
    await session.signIn('ada@example.com', 'secret');
    server.isOffline = true;

    await expectLater(
      session.manager.validToken(),
      throwsA(isA<Transient>()),
    );

    expect((await session.manager.current())?.accessToken, 'access-1');
  });
}
```

- [ ] **Step 8: Run it to see it fail**

Run: `cd packages/token_manager && dart test test/recipes/login_and_set_tokens_test.dart`
Expected: FAIL to compile: the example `example/recipes/login_and_set_tokens.dart` does not exist yet.

- [ ] **Step 9: Write the example**

Create `packages/token_manager/example/recipes/login_and_set_tokens.dart`. It is the code the page shows; it uses only the public API, and every stand-in is a public class so the page can name it.

```dart
import 'dart:io';

import 'package:token_manager/token_manager.dart';

/// What the token endpoint of your auth server answers.
typedef TokenResponse = ({
  String accessToken,
  String refreshToken,
  Duration expiresIn,
});

/// Turns a server answer into the tokens the manager stores.
extension TokenResponseTokens on TokenResponse {
  /// The tokens, expiring [expiresIn] from now.
  TokenSet toTokenSet() => TokenSet(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: DateTime.now().add(expiresIn),
  );
}

/// The server rejected the credentials or the refresh token for good.
final class GrantRejected implements Exception {
  /// Creates the exception.
  const GrantRejected();
}

/// Your auth server; implement it with the HTTP client you already use.
abstract interface class AuthApi {
  /// Exchanges an email and a password for tokens.
  Future<TokenResponse> signIn(String email, String password);

  /// Exchanges a refresh token for new tokens.
  Future<TokenResponse> refresh(String refreshToken);
}

/// Refreshes through [AuthApi]; the manager calls it, never your code.
final class ApiRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher over [api].
  const ApiRefresher(this._api);

  final AuthApi _api;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    final refreshToken = current.refreshToken;
    if (refreshToken == null) {
      throw const InvalidGrant();
    }
    try {
      return (await _api.refresh(refreshToken)).toTokenSet();
    } on GrantRejected {
      // The server said the refresh token is dead: the user must sign in
      // again. Any other exception, such as a network error, is Transient.
      throw const InvalidGrant();
    }
  }
}

/// One signed-in session: a manager plus the sign-in and sign-out calls.
final class Session {
  /// Creates a session over [api]; [store] defaults to memory.
  Session({required AuthApi api, TokenStore<TokenSet>? store})
    : _api = api,
      manager = TokenManager<TokenSet>.create(
        store: store ?? InMemoryTokenStore<TokenSet>(),
        refresher: ApiRefresher(api),
        info: const TokenSetInfo(),
      );

  /// The manager every adapter and repository shares.
  final TokenManager<TokenSet> manager;

  final AuthApi _api;

  /// Signs in and stores the tokens; throws [GrantRejected] on bad credentials.
  Future<void> signIn(String email, String password) async {
    final response = await _api.signIn(email, password);
    await manager.setTokens(response.toTokenSet());
  }

  /// Removes the tokens; the state becomes `Unauthenticated`.
  Future<void> signOut() => manager.logout();

  /// Releases the manager.
  Future<void> dispose() => manager.dispose();
}

// ---- Stand-in for your auth server, so this file runs without a network.

/// Answers like a token endpoint: any password but `wrong` signs in.
final class StandInAuthServer implements AuthApi {
  /// Creates a server whose access tokens live [lifetime].
  StandInAuthServer({this.lifetime = const Duration(hours: 1)});

  /// How long an issued access token lives.
  final Duration lifetime;

  /// When true, every refresh fails like a network error.
  bool isOffline = false;

  /// When true, the refresh token is rejected for good.
  bool isRevoked = false;

  /// How many refreshes reached the server.
  int refreshes = 0;

  TokenResponse _issue(int number) => (
    accessToken: 'access-$number',
    refreshToken: 'refresh-$number',
    expiresIn: lifetime,
  );

  @override
  Future<TokenResponse> signIn(String email, String password) async {
    if (password == 'wrong') {
      throw const GrantRejected();
    }
    return _issue(1);
  }

  @override
  Future<TokenResponse> refresh(String refreshToken) async {
    if (isOffline) {
      throw const SocketException('offline');
    }
    if (isRevoked) {
      throw const GrantRejected();
    }
    refreshes++;
    return _issue(refreshes + 1);
  }
}

Future<void> main() async {
  final session = Session(api: StandInAuthServer());

  await session.signIn('ada@example.com', 'correct horse');
  final tokens = await session.manager.validToken();
  stdout.writeln('Signed in with ${tokens.accessToken}');

  await session.signOut();
  stdout.writeln('Signed out: ${await session.manager.current() == null}');

  await session.dispose();
}
```

- [ ] **Step 10: Run the test to see it pass; run the example**

Run: `cd packages/token_manager && dart test test/recipes/login_and_set_tokens_test.dart`
Expected: PASS, 6 tests.

Run: `cd packages/token_manager && dart run example/recipes/login_and_set_tokens.dart`
Expected: it exits with code 0 (it prints a short walk-through).

- [ ] **Step 11: Run the docs test to see it fail, then write the page**

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: FAIL: `every recipe example is included by a page of its package` names `packages/token_manager/example/recipes/login_and_set_tokens.dart`.

Create `packages/token_manager/doc/recipes/login_and_set_tokens.md` (create the folder first). The line `<!-- include: ... -->` stays as written; the script of this task expands it into a `dart` block:

```markdown
# Recipe: sign in and store the tokens

Sign the user in against your token endpoint, hand the tokens to
`TokenManager.setTokens`, and let the manager refresh them from then on.
Use this when a Dart or Flutter app has an access token and a refresh token
and nothing yet that refreshes them.

## The code

`ApiRefresher` is the only place that talks to the refresh endpoint,
`Session` creates the one manager of the app, and `StandInAuthServer` lets
the file run without a network. Replace `AuthApi` with your HTTP client.

<!-- include: example/recipes/login_and_set_tokens.dart -->

Run it with `dart run example/recipes/login_and_set_tokens.dart`. The test
`test/recipes/login_and_set_tokens_test.dart` checks every behaviour below.

## What you get

- `signIn` stores the tokens; wrong credentials leave the session signed out.
- Tokens that expire within the skew (30 seconds by default) are refreshed
  before `validToken()` or `authorize` returns them. Concurrent callers share
  one refresh.
- A rejected refresh token (`GrantRejected` here) becomes `InvalidGrant`: the
  manager signs the session out and `current()` returns `null`.
- A network failure becomes `Transient`: the session and its tokens stay, and
  the next call retries.

## Common mistakes

- **Forgetting `info: const TokenSetInfo()`.** Without a `TokenInfo` the
  manager treats tokens as never expiring and refreshes only after a server
  rejected them.
- **Throwing `InvalidGrant` for a network error.** It signs the user out. Throw
  it only when the server said the refresh token is dead.
- **Returning the old refresh token.** When the server rotates refresh tokens
  the answer carries a new one; return it, or the next refresh fails.
- **Creating a second manager for the same session.** Single-flight is per
  manager; two managers refresh twice. Share the one in `Session`.
- **Calling `setTokens` from the refresher.** The manager stores what
  `refresh` returns; `setTokens` is for sign-in.

## See also

- [Getting started](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/getting_started.md)
- [Refreshing and failures](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/refreshing.md)
```

Expand the include and check:

```bash
python3 /tmp/assemble_recipe.py packages/token_manager/doc/recipes/login_and_set_tokens.md
```

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: PASS (the page includes the file verbatim, has no relative link and no banned wording).

- [ ] **Step 12: Format, analyze, commit**

Run: `dart format packages && dart analyze packages/token_manager packages/docs_check`
Expected: `0 changed` and `No issues found!`.

```bash
git add packages/token_manager/example/recipes/login_and_set_tokens.dart packages/token_manager/test/recipes/login_and_set_tokens_test.dart packages/token_manager/doc/recipes/login_and_set_tokens.md
git commit -m "docs(token_manager): add the Sign in and store the tokens recipe" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

#### Recipe `secure_token_store` (Keep the session in secure storage)

Public names of the example (the test and the page use them): `SecretBox`, `SecureTokenStore`, `MemorySecretBox`.

- [ ] **Step 13: Write the test of `secure_token_store`**

Create `packages/token_manager/test/recipes/secure_token_store_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/secure_token_store.dart'
    show MemorySecretBox, SecureTokenStore;

void main() {
  // Assigned in setUp, which runs before every test.
  late MemorySecretBox box;
  late SecureTokenStore store;
  final tokens = TokenSet(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: DateTime.utc(2030),
  );

  setUp(() {
    box = MemorySecretBox();
    store = SecureTokenStore(box);
  });

  test('read returns null when nothing is stored', () async {
    expect(await store.read(), isNull);
  });

  test('write then read returns the same tokens', () async {
    await store.write(tokens);

    expect(await store.read(), tokens);
  });

  test(
    'tokens without a refresh token or expiry survive a round trip',
    () async {
      const bare = TokenSet(accessToken: 'access');

      await store.write(bare);

      expect(await store.read(), bare);
    },
  );

  test('delete removes the entry from the box', () async {
    await store.write(tokens);

    await store.delete();

    expect(box.values, isEmpty);
  });

  test('a damaged entry reads as signed out', () async {
    box.values['auth.tokens'] = '{not json';

    expect(await store.read(), isNull);
  });

  test('an entry with the wrong shape reads as signed out', () async {
    box.values['auth.tokens'] = '{"accessToken": 1}';

    expect(await store.read(), isNull);
  });

  test('a new manager restores the session after a restart', () async {
    final first = TokenManager<TokenSet>.create(store: store);
    await first.setTokens(tokens);
    await first.dispose();

    final second = TokenManager<TokenSet>.create(
      store: SecureTokenStore(box),
    );

    expect(await second.current(), tokens);
    await second.dispose();
  });

  test('logout empties the box', () async {
    final manager = TokenManager<TokenSet>.create(store: store);
    await manager.setTokens(tokens);

    await manager.logout();

    expect(box.values, isEmpty);
    await manager.dispose();
  });
}
```

- [ ] **Step 14: Run it to see it fail**

Run: `cd packages/token_manager && dart test test/recipes/secure_token_store_test.dart`
Expected: FAIL to compile: the example `example/recipes/secure_token_store.dart` does not exist yet.

- [ ] **Step 15: Write the example**

Create `packages/token_manager/example/recipes/secure_token_store.dart`. It is the code the page shows; it uses only the public API, and every stand-in is a public class so the page can name it.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:token_manager/token_manager.dart';

/// A key-value box in secure storage (Keychain, Keystore); implement it with
/// the secure-storage plugin of your platform.
abstract interface class SecretBox {
  /// Returns the value of [key], or `null`.
  Future<String?> read(String key);

  /// Stores [value] under [key].
  Future<void> write(String key, String value);

  /// Removes [key].
  Future<void> delete(String key);
}

/// Keeps a `TokenSet` as JSON in a [SecretBox], so the session survives a
/// restart of the app.
final class SecureTokenStore implements TokenStore<TokenSet> {
  /// Creates a store over [_box].
  const SecureTokenStore(this._box);

  static const String _key = 'auth.tokens';

  final SecretBox _box;

  @override
  Future<TokenSet?> read() async {
    final raw = await _box.read(_key);
    return raw == null ? null : _decode(raw);
  }

  @override
  Future<void> write(TokenSet tokens) {
    return _box.write(
      _key,
      jsonEncode({
        'accessToken': tokens.accessToken,
        'refreshToken': tokens.refreshToken,
        'expiresAt': tokens.expiresAt?.toIso8601String(),
      }),
    );
  }

  @override
  Future<void> delete() => _box.delete(_key);

  /// Returns `null` for a payload that cannot be read, so a damaged entry
  /// means "signed out" and the next sign-in replaces it.
  TokenSet? _decode(String raw) {
    try {
      return switch (jsonDecode(raw)) {
        {
          'accessToken': final String access,
          'refreshToken': final String? refresh,
          'expiresAt': final String? expires,
        } =>
          TokenSet(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expires == null ? null : DateTime.parse(expires),
          ),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }
}

// ---- Stand-in for secure storage, so this file runs without a device.

/// A [SecretBox] that keeps its values in a map.
final class MemorySecretBox implements SecretBox {
  /// The stored values by key.
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

Future<void> main() async {
  final box = MemorySecretBox();

  final first = TokenManager<TokenSet>.create(
    store: SecureTokenStore(box),
    info: const TokenSetInfo(),
  );
  await first.setTokens(
    TokenSet(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );
  await first.dispose();

  // A new manager over the same box, as after a restart of the app.
  final second = TokenManager<TokenSet>.create(
    store: SecureTokenStore(box),
    info: const TokenSetInfo(),
  );
  stdout.writeln('Restored: ${(await second.current())?.accessToken}');
  await second.dispose();
}
```

- [ ] **Step 16: Run the test to see it pass; run the example**

Run: `cd packages/token_manager && dart test test/recipes/secure_token_store_test.dart`
Expected: PASS, 8 tests.

Run: `cd packages/token_manager && dart run example/recipes/secure_token_store.dart`
Expected: it exits with code 0 (it prints a short walk-through).

- [ ] **Step 17: Run the docs test to see it fail, then write the page**

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: FAIL: `every recipe example is included by a page of its package` names `packages/token_manager/example/recipes/secure_token_store.dart`.

Create `packages/token_manager/doc/recipes/secure_token_store.md` (create the folder first). The line `<!-- include: ... -->` stays as written; the script of this task expands it into a `dart` block:

```markdown
# Recipe: keep the session in secure storage

Make the session survive a restart of the app by writing the tokens to secure
storage (Keychain, Keystore) through a custom `TokenStore`. Use this when the
user must stay signed in after the process ends.

## The code

`SecretBox` is the three-method key-value box you back with the secure-storage
plugin of your platform. `SecureTokenStore` stores a `TokenSet` in it as JSON.
`MemorySecretBox` stands in for the plugin so the file runs anywhere.

<!-- include: example/recipes/secure_token_store.dart -->

Run it with `dart run example/recipes/secure_token_store.dart`. The test
`test/recipes/secure_token_store_test.dart` checks every behaviour below.

## What you get

- A new manager over the same box finds the tokens again: the manager reads the
  store lazily, on the first `current`, `validToken` or `authorize`.
- `setTokens` publishes the tokens to `states` only after `write` succeeded.
- `logout` and a dead refresh token call `delete`, so the box is empty.
- A damaged or unknown entry reads as signed out, and the next sign-in replaces
  it.

## Common mistakes

- **Using plain preferences or a file.** Those are not encrypted; keep tokens in
  secure storage.
- **Looking for an `initialize()` step.** There is none; loading is lazy.
- **Swallowing every exception in `read`.** A `read` that throws fails the
  call that triggered the load, and the next call retries. Return `null` only
  for data you know is unreadable, as `_decode` does.
- **Expecting a failed write after a refresh to be reported.** The server has
  already rotated the old pair, so the refreshed tokens stay in memory until
  the next write; see the storage guide.
- **Sharing one key between users.** Use one key per signed-in account, or
  delete the entry on sign-out.

## See also

- [Storage guide](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/storage.md)
```

Expand the include and check:

```bash
python3 /tmp/assemble_recipe.py packages/token_manager/doc/recipes/secure_token_store.md
```

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: PASS (the page includes the file verbatim, has no relative link and no banned wording).

- [ ] **Step 18: Format, analyze, commit**

Run: `dart format packages && dart analyze packages/token_manager packages/docs_check`
Expected: `0 changed` and `No issues found!`.

```bash
git add packages/token_manager/example/recipes/secure_token_store.dart packages/token_manager/test/recipes/secure_token_store_test.dart packages/token_manager/doc/recipes/secure_token_store.md
git commit -m "docs(token_manager): add the Keep the session in secure storage recipe" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

#### Recipe `session_expiry` (Send the user to sign-in when the session ends)

Public names of the example (the test and the page use them): `SessionWatcher`, `RevokedRefresher`.

- [ ] **Step 19: Write the test of `session_expiry`**

Create `packages/token_manager/test/recipes/session_expiry_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/session_expiry.dart'
    show RevokedRefresher, SessionWatcher;
import '../helpers/fake_clock.dart';

final class _TransientRefresher implements TokenRefresher<TokenSet> {
  const _TransientRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    throw const Transient('offline');
  }
}

void main() {
  final clock = FakeClock(DateTime.utc(2026));
  // Assigned in setUp, which runs before every test.
  late int signedOut;

  TokenSet expiring() => TokenSet(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: clock.now().add(const Duration(seconds: 5)),
  );

  TokenManager<TokenSet> managerWith(TokenRefresher<TokenSet> refresher) =>
      TokenManager<TokenSet>.create(
        store: InMemoryTokenStore<TokenSet>(),
        refresher: refresher,
        info: const TokenSetInfo(),
        clock: clock,
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() => signedOut = 0);

  test('an app that starts signed out is not reported', () async {
    final manager = managerWith(const RevokedRefresher());
    final watcher = SessionWatcher(manager)
      ..watch(onSignedOut: () => signedOut++);

    await settle();

    expect(signedOut, 0);
    await watcher.close();
    await manager.dispose();
  });

  test('a rejected refresh token reports the end of the session', () async {
    final manager = managerWith(const RevokedRefresher());
    final watcher = SessionWatcher(manager)
      ..watch(onSignedOut: () => signedOut++);
    await manager.setTokens(expiring());

    await expectLater(manager.validToken(), throwsA(isA<InvalidGrant>()));
    await settle();

    expect(signedOut, 1);
    await watcher.close();
    await manager.dispose();
  });

  test('logout reports the end of the session once', () async {
    final manager = managerWith(const RevokedRefresher());
    final watcher = SessionWatcher(manager)
      ..watch(onSignedOut: () => signedOut++);
    await manager.setTokens(expiring());

    await manager.logout();
    await manager.logout();
    await settle();

    expect(signedOut, 1);
    await watcher.close();
    await manager.dispose();
  });

  test('a transient refresh failure keeps the session', () async {
    final manager = managerWith(const _TransientRefresher());
    final watcher = SessionWatcher(manager)
      ..watch(onSignedOut: () => signedOut++);
    await manager.setTokens(expiring());

    await expectLater(manager.validToken(), throwsA(isA<Transient>()));
    await settle();

    expect(signedOut, 0);
    expect(await manager.current(), isNotNull);
    await watcher.close();
    await manager.dispose();
  });
}
```

- [ ] **Step 20: Run it to see it fail**

Run: `cd packages/token_manager && dart test test/recipes/session_expiry_test.dart`
Expected: FAIL to compile: the example `example/recipes/session_expiry.dart` does not exist yet.

- [ ] **Step 21: Write the example**

Create `packages/token_manager/example/recipes/session_expiry.dart`. It is the code the page shows; it uses only the public API, and every stand-in is a public class so the page can name it.

```dart
import 'dart:async';
import 'dart:io';

import 'package:token_manager/token_manager.dart';

/// Tells the app when a signed-in session ends, so it can show the sign-in
/// screen.
///
/// The session ends when the refresh token is rejected for good
/// (`InvalidGrant`) or when the app calls `logout`. A failed refresh that may
/// go away (`Transient`) does not end it.
final class SessionWatcher {
  /// Creates a watcher over [_manager].
  SessionWatcher(this._manager);

  final TokenManager<TokenSet> _manager;
  StreamSubscription<AuthState<TokenSet>>? _subscription;

  /// Calls [onSignedOut] each time a signed-in session ends.
  ///
  /// `states` replays the current state to a new listener, so the first
  /// `Unauthenticated` of an app that starts signed out is not reported.
  void watch({required void Function() onSignedOut}) {
    var wasSignedIn = false;
    _subscription = _manager.states.listen((state) {
      switch (state) {
        case Unauthenticated<TokenSet>():
          if (wasSignedIn) {
            wasSignedIn = false;
            onSignedOut();
          }
        case Authenticated<TokenSet>() || Refreshing<TokenSet>():
          wasSignedIn = true;
      }
    });
  }

  /// Stops watching.
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

// ---- Stand-in for a revoked session, so this file runs without a server.

/// A refresher whose server has revoked the session.
final class RevokedRefresher implements TokenRefresher<TokenSet> {
  /// Creates the refresher.
  const RevokedRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    throw const InvalidGrant();
  }
}

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: const RevokedRefresher(),
    info: const TokenSetInfo(),
  );
  final watcher = SessionWatcher(manager)
    ..watch(onSignedOut: () => stdout.writeln('Show the sign-in screen'));

  await manager.setTokens(
    TokenSet(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(seconds: 5)),
    ),
  );
  try {
    await manager.validToken();
  } on InvalidGrant {
    stdout.writeln('The refresh token was rejected');
  }
  await Future<void>.delayed(Duration.zero);

  await watcher.close();
  await manager.dispose();
}
```

- [ ] **Step 22: Run the test to see it pass; run the example**

Run: `cd packages/token_manager && dart test test/recipes/session_expiry_test.dart`
Expected: PASS, 4 tests.

Run: `cd packages/token_manager && dart run example/recipes/session_expiry.dart`
Expected: it exits with code 0 (it prints a short walk-through).

- [ ] **Step 23: Run the docs test to see it fail, then write the page**

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: FAIL: `every recipe example is included by a page of its package` names `packages/token_manager/example/recipes/session_expiry.dart`.

Create `packages/token_manager/doc/recipes/session_expiry.md` (create the folder first). The line `<!-- include: ... -->` stays as written; the script of this task expands it into a `dart` block:

```markdown
# Recipe: send the user to sign-in when the session ends

React to logout and to a dead refresh token from one place, the `states`
stream, instead of catching `InvalidGrant` around every call.

## The code

`SessionWatcher` listens to `TokenManager.states` and calls your callback when
a signed-in session ends. `RevokedRefresher` stands in for a server that has
revoked the session.

<!-- include: example/recipes/session_expiry.dart -->

Run it with `dart run example/recipes/session_expiry.dart`. The test
`test/recipes/session_expiry_test.dart` checks every behaviour below.

## What you get

- An app that starts signed out is not reported: `states` replays the current
  state to a new listener, and the watcher ignores an `Unauthenticated` that
  did not follow a signed-in state.
- A rejected refresh token (`InvalidGrant`) ends the session and calls the
  callback once.
- `logout()` calls the callback once, however often it is called.
- A `Transient` refresh failure keeps the session and does not call it.

## Common mistakes

- **Treating the first `Unauthenticated` as an expiry.** It is the replay of
  the initial state; the login screen would flash at start-up.
- **Treating `Refreshing` as signed out.** The session is still valid while a
  refresh runs.
- **Expecting a timer.** Refresh is on demand: a session that dies while the app
  is idle is noticed on the next `validToken` or `authorize`.
- **Navigating from inside a `TokenRefresher`.** The refresher only talks to the
  token endpoint; navigation belongs in the state listener.
- **Forgetting `close()`.** Cancel the subscription when the screen or scope
  that owns the watcher goes away.

## See also

- [Concepts and session state](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/concepts.md)
- [Streams](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/streams.md)
```

Expand the include and check:

```bash
python3 /tmp/assemble_recipe.py packages/token_manager/doc/recipes/session_expiry.md
```

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: PASS (the page includes the file verbatim, has no relative link and no banned wording).

- [ ] **Step 24: Format, analyze, commit**

Run: `dart format packages && dart analyze packages/token_manager packages/docs_check`
Expected: `0 changed` and `No issues found!`.

```bash
git add packages/token_manager/example/recipes/session_expiry.dart packages/token_manager/test/recipes/session_expiry_test.dart packages/token_manager/doc/recipes/session_expiry.md
git commit -m "docs(token_manager): add the Send the user to sign-in when the session ends recipe" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

#### Recipe `testing_without_network` (Test code that uses tokens without a network)

Public names of the example (the test and the page use them): `ProfileApi`, `UnauthorizedException`, `ProfileRepository`, `FixedClock`, `CountingRefresher`, `FakeProfileApi`.

- [ ] **Step 25: Write the test of `testing_without_network`**

Create `packages/token_manager/test/recipes/testing_without_network_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/testing_without_network.dart';

void main() {
  // Assigned in setUp, which runs before every test.
  late FixedClock clock;

  TokenManager<TokenSet> managerFor(
    CountingRefresher refresher,
    Duration life,
  ) {
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(
        TokenSet(
          accessToken: 'stale',
          refreshToken: 'refresh',
          expiresAt: clock.current.add(life),
        ),
      ),
      refresher: refresher,
      info: const TokenSetInfo(),
      clock: clock,
    );
    addTearDown(manager.dispose);
    return manager;
  }

  setUp(() => clock = FixedClock(DateTime.utc(2026)));

  test('tokens inside the skew are refreshed before the call', () async {
    final refresher = CountingRefresher();
    final api = FakeProfileApi({'fresh-1'});
    final repository = ProfileRepository(
      managerFor(refresher, const Duration(seconds: 10)),
      api,
    );

    await repository.load();

    expect(api.seen, ['fresh-1']);
    expect(refresher.calls, 1);
  });

  test('valid tokens are sent without a refresh', () async {
    final refresher = CountingRefresher();
    final api = FakeProfileApi({'stale'});
    final repository = ProfileRepository(
      managerFor(refresher, const Duration(hours: 1)),
      api,
    );

    await repository.load();

    expect(api.seen, ['stale']);
    expect(refresher.calls, 0);
  });

  test('a rejected token is refreshed and the call replayed once', () async {
    final refresher = CountingRefresher();
    final api = FakeProfileApi({'fresh-1'});
    final repository = ProfileRepository(
      managerFor(refresher, const Duration(hours: 1)),
      api,
    );

    await repository.load();

    expect(api.seen, ['stale', 'fresh-1']);
    expect(refresher.calls, 1);
  });

  test('a dead refresh token fails the call and signs out', () async {
    final manager = managerFor(
      CountingRefresher(failure: const InvalidGrant()),
      const Duration(hours: 1),
    );
    final repository = ProfileRepository(manager, FakeProfileApi({'fresh-1'}));

    await expectLater(repository.load(), throwsA(isA<InvalidGrant>()));

    expect(await manager.current(), isNull);
  });
}
```

- [ ] **Step 26: Run it to see it fail**

Run: `cd packages/token_manager && dart test test/recipes/testing_without_network_test.dart`
Expected: FAIL to compile: the example `example/recipes/testing_without_network.dart` does not exist yet.

- [ ] **Step 27: Write the example**

Create `packages/token_manager/example/recipes/testing_without_network.dart`. It is the code the page shows; it uses only the public API, and every stand-in is a public class so the page can name it.

```dart
import 'dart:io';

import 'package:token_manager/token_manager.dart';

/// The endpoint your repository calls; implement it with your HTTP client.
abstract interface class ProfileApi {
  /// Returns the profile, or throws [UnauthorizedException] on a 401.
  Future<String> fetchProfile(String accessToken);
}

/// The server rejected the access token.
final class UnauthorizedException implements Exception {
  /// Creates the exception.
  const UnauthorizedException();
}

/// The code under test: it asks the manager for valid tokens on every call.
final class ProfileRepository {
  /// Creates a repository over [_manager] and [_api].
  const ProfileRepository(this._manager, this._api);

  final TokenManager<TokenSet> _manager;
  final ProfileApi _api;

  /// Loads the profile, refreshing the tokens first when they are about to
  /// expire and replaying the call once when the server rejects them.
  Future<String> load() {
    return _manager.authorize(
      (tokens) => _api.fetchProfile(tokens.accessToken),
      isAuthFailure: (error) => error is UnauthorizedException,
    );
  }
}

// ---- Test doubles; none of them touches the network.

/// A clock that only moves when the test says so.
final class FixedClock implements Clock {
  /// Creates a clock reading [current].
  FixedClock(this.current);

  /// The time the clock reads.
  DateTime current;

  @override
  DateTime now() => current;
}

/// A refresher that counts its calls, or fails with [failure].
final class CountingRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher that succeeds unless [failure] is set.
  CountingRefresher({this.failure});

  /// What every call throws; `null` makes calls succeed.
  final RefreshFailure? failure;

  /// How many times [refresh] was called.
  int calls = 0;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    calls++;
    final error = failure;
    if (error != null) {
      throw error;
    }
    return TokenSet(
      accessToken: 'fresh-$calls',
      refreshToken: 'refresh-$calls',
      expiresAt: DateTime.utc(2030),
    );
  }
}

/// A server that accepts only the access tokens in [accepted].
final class FakeProfileApi implements ProfileApi {
  /// Creates a server for [accepted] access tokens.
  FakeProfileApi(this.accepted);

  /// The access tokens the server answers 200 to.
  final Set<String> accepted;

  /// Every access token the server received, in order.
  final List<String> seen = [];

  @override
  Future<String> fetchProfile(String accessToken) async {
    seen.add(accessToken);
    if (!accepted.contains(accessToken)) {
      throw const UnauthorizedException();
    }
    return 'profile of ada';
  }
}

Future<void> main() async {
  final clock = FixedClock(DateTime.utc(2026));
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: CountingRefresher(),
    info: const TokenSetInfo(),
    clock: clock,
  );
  await manager.setTokens(
    TokenSet(
      accessToken: 'stale',
      refreshToken: 'refresh',
      expiresAt: clock.current.add(const Duration(seconds: 10)),
    ),
  );

  final api = FakeProfileApi({'fresh-1'});
  final profile = await ProfileRepository(manager, api).load();
  stdout.writeln('$profile after sending ${api.seen}');

  await manager.dispose();
}
```

- [ ] **Step 28: Run the test to see it pass; run the example**

Run: `cd packages/token_manager && dart test test/recipes/testing_without_network_test.dart`
Expected: PASS, 4 tests.

Run: `cd packages/token_manager && dart run example/recipes/testing_without_network.dart`
Expected: it exits with code 0 (it prints a short walk-through).

- [ ] **Step 29: Run the docs test to see it fail, then write the page**

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: FAIL: `every recipe example is included by a page of its package` names `packages/token_manager/example/recipes/testing_without_network.dart`.

Create `packages/token_manager/doc/recipes/testing_without_network.md` (create the folder first). The line `<!-- include: ... -->` stays as written; the script of this task expands it into a `dart` block:

```markdown
# Recipe: test code that uses tokens without a network

Test a repository that calls `TokenManager.authorize` with a fake clock, a
counting refresher and a fake server. Nothing here touches the network and no
test waits for real time.

## The code

`ProfileRepository` is the code under test. `FixedClock`, `CountingRefresher`
and `FakeProfileApi` are the doubles; copy them next to your tests.

<!-- include: example/recipes/testing_without_network.dart -->

## The tests

<!-- include: test/recipes/testing_without_network_test.dart -->

In your project import your own repository instead of the recipe file.

## What you get

- Tokens inside the skew are refreshed before the call, by moving the clock
  or by creating them with a near expiry; valid tokens are sent as they are.
- A rejected token is refreshed once and the call replayed once.
- A dead refresh token fails the call with `InvalidGrant` and signs out.

## Common mistakes

- **Sleeping until a token expires.** Pass a `Clock` to `TokenManager.create`
  and move it.
- **Sharing one manager between tests.** Its state leaks; create one per test
  and dispose it, as `addTearDown(manager.dispose)` does.
- **Mocking `TokenManager`.** Use the real manager with an `InMemoryTokenStore`
  and a fake refresher; the refresh rules are what you want under test.
- **Asserting before the refresh finished.** Await the repository call first,
  then check the refresher.

## See also

- [Testing guide](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/testing.md)
```

Expand the include and check:

```bash
python3 /tmp/assemble_recipe.py packages/token_manager/doc/recipes/testing_without_network.md
```

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: PASS (the page includes the file verbatim, has no relative link and no banned wording).

- [ ] **Step 30: Format, analyze, commit**

Run: `dart format packages && dart analyze packages/token_manager packages/docs_check`
Expected: `0 changed` and `No issues found!`.

```bash
git add packages/token_manager/example/recipes/testing_without_network.dart packages/token_manager/test/recipes/testing_without_network_test.dart packages/token_manager/doc/recipes/testing_without_network.md
git commit -m "docs(token_manager): add the Test code that uses tokens without a network recipe" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 31: List the recipes in the token_manager README**

Edit `packages/token_manager/README.md`: add the table-of-contents entry and the section before `## Reference`.

Edit 1. Replace

```markdown
- [Reference](#reference)
```

with

```markdown
- [Recipes](#recipes)
- [Reference](#reference)
```

Edit 2. Replace

```markdown

## Reference
```

with

```markdown

## Recipes

Each recipe is one page with complete code that is compiled and tested in this repository.

- [Sign in and store the tokens](doc/recipes/login_and_set_tokens.md)
- [Keep the session in secure storage](doc/recipes/secure_token_store.md)
- [Send the user to sign-in when the session ends](doc/recipes/session_expiry.md)
- [Test code that uses tokens without a network](doc/recipes/testing_without_network.md)

## Reference
```

Run: `cd packages/docs_check && dart test test/readme_test.dart`
Expected: PASS.

```bash
git add packages/token_manager/README.md
git commit -m "docs(token_manager): list the recipes in the README" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

### Task 4: Dio recipes

**Files:**
- Create: `packages/token_manager_dio/example/recipes/replace_refresh_interceptor.dart`, `packages/token_manager_dio/test/recipes/replace_refresh_interceptor_test.dart`, `packages/token_manager_dio/doc/recipes/replace_refresh_interceptor.md`
- Create: `packages/token_manager_dio/example/recipes/skip_auth_endpoints.dart`, `packages/token_manager_dio/test/recipes/skip_auth_endpoints_test.dart`, `packages/token_manager_dio/doc/recipes/skip_auth_endpoints.md`
- Modify: `packages/token_manager_dio/README.md`

**Interfaces:**
- Consumes: the recipe procedure and `/tmp/assemble_recipe.py` (Task 3); `packages/docs_check/test/recipe_pages_test.dart` (Task 3).
- Produces: the public classes listed under each recipe; later tasks do not depend on them.

Notes for the implementer:
- `skip_auth_endpoints_test.dart` contains the pinned test `mistake: a refresh sent through the interceptor Dio waits for itself`. It builds a manager whose refresher sends the refresh through the *interceptor* `Dio` and expects the call not to complete within 300 ms. This is the documented deadlock (the manager waits for the refresh, the request waits for the manager). If this test fails after the `chore/patch-releases` merge, the engine changed: change the test and the sentence under "Common mistakes" together, never delete one of them.
- `replace_refresh_interceptor_test.dart` includes the test `a refresh that renews nothing sends the request only once` (a refresher that returns the same token: the request is sent once, with `Bearer stale`).

#### Recipe `replace_refresh_interceptor` (Replace a hand-written refresh interceptor)

Public names of the example (the test and the page use them): `BearerDelegate`, `ApiClient`, `StandInRefresher`, `StandInServer`.

- [ ] **Step 1: Write the test of `replace_refresh_interceptor`**

Create `packages/token_manager_dio/test/recipes/replace_refresh_interceptor_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/replace_refresh_interceptor.dart'
    show ApiClient, StandInRefresher, StandInServer;

void main() {
  // Assigned in setUp, which runs before every test.
  late StandInRefresher refresher;
  late StandInServer server;
  late TokenManager<TokenSet> manager;
  late ApiClient api;

  setUp(() {
    refresher = StandInRefresher();
    server = StandInServer();
    manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(
        const TokenSet(accessToken: 'stale', refreshToken: 'refresh-1'),
      ),
      refresher: refresher,
    );
    api = ApiClient(
      manager: manager,
      baseUrl: 'https://api.test',
      adapter: server,
    );
  });

  tearDown(() => manager.dispose());

  test('parallel 401s share one refresh', () async {
    await Future.wait([
      api.dio.get<Object?>('/a'),
      api.dio.get<Object?>('/b'),
      api.dio.get<Object?>('/c'),
    ]);

    expect(refresher.calls, 1);
  });

  test('each rejected request is replayed once with the new token', () async {
    final responses = await Future.wait([
      api.dio.get<Object?>('/a'),
      api.dio.get<Object?>('/b'),
    ]);

    expect(responses.map((response) => response.statusCode), [200, 200]);
    expect(server.received, [
      'Bearer stale',
      'Bearer stale',
      'Bearer fresh',
      'Bearer fresh',
    ]);
  });

  test('a refresh that renews nothing sends the request only once', () async {
    final stubborn = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(
        const TokenSet(accessToken: 'stale', refreshToken: 'refresh-1'),
      ),
      refresher: _SameTokenRefresher(),
    );
    final client = ApiClient(
      manager: stubborn,
      baseUrl: 'https://api.test',
      adapter: server,
    );

    await expectLater(
      client.dio.get<Object?>('/a'),
      throwsA(isA<DioException>()),
    );

    expect(server.received, ['Bearer stale']);
    await stubborn.dispose();
  });

  test('a dead refresh token reaches the caller as InvalidGrant', () async {
    final dead = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(
        const TokenSet(accessToken: 'stale', refreshToken: 'refresh-1'),
      ),
      refresher: _DeadRefresher(),
    );
    final client = ApiClient(
      manager: dead,
      baseUrl: 'https://api.test',
      adapter: server,
    );

    await expectLater(
      client.dio.get<Object?>('/a'),
      throwsA(
        isA<DioException>().having(
          (error) => error.error,
          'error',
          isA<InvalidGrant>(),
        ),
      ),
    );
    await dead.dispose();
  });
}

final class _SameTokenRefresher implements TokenRefresher<TokenSet> {
  @override
  Future<TokenSet> refresh(TokenSet current) async => current;
}

final class _DeadRefresher implements TokenRefresher<TokenSet> {
  @override
  Future<TokenSet> refresh(TokenSet current) async {
    throw const InvalidGrant();
  }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/token_manager_dio && dart test test/recipes/replace_refresh_interceptor_test.dart`
Expected: FAIL to compile: the example `example/recipes/replace_refresh_interceptor.dart` does not exist yet.

- [ ] **Step 3: Write the example**

Create `packages/token_manager_dio/example/recipes/replace_refresh_interceptor.dart`. It is the code the page shows; it uses only the public API, and every stand-in is a public class so the page can name it.

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

/// Writes the access token into the `Authorization` header.
final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  /// Creates the delegate.
  const BearerDelegate();

  @override
  void applyTo(RequestOptions options, TokenSet tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
  }
}

/// A [Dio] for your API that attaches tokens, refreshes once for any number
/// of parallel 401s and replays each rejected request once.
final class ApiClient {
  /// Creates the client; [adapter] replaces the network in tests.
  ApiClient({
    required TokenManager<TokenSet> manager,
    required String baseUrl,
    HttpClientAdapter? adapter,
  }) : dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
    }
    dio.interceptors.add(
      DioTokenInterceptor<TokenSet>(
        manager: manager,
        delegate: const BearerDelegate(),
        // The Dio the interceptor is added to: the replay keeps its adapter,
        // its other interceptors and its timeouts.
        dio: dio,
      ),
    );
  }

  /// The client to use for every authorized call.
  final Dio dio;
}

// ---- Stand-ins for the network and the token endpoint, so this file runs
// ---- without either.

/// A refresher that counts its calls and issues `fresh` tokens.
final class StandInRefresher implements TokenRefresher<TokenSet> {
  /// How many times [refresh] was called.
  int calls = 0;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    calls++;
    return const TokenSet(accessToken: 'fresh', refreshToken: 'refresh-2');
  }
}

/// A server that answers 401 to every access token but `fresh`.
final class StandInServer implements HttpClientAdapter {
  /// The `Authorization` header of every request, in arrival order.
  final List<String?> received = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final authorization = options.headers['Authorization'];
    received.add(authorization is String ? authorization : null);
    final isAccepted = authorization == 'Bearer fresh';
    return ResponseBody.fromString(
      isAccepted ? jsonEncode({'me': 'ada'}) : '',
      isAccepted ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> main() async {
  final refresher = StandInRefresher();
  final server = StandInServer();
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(
      const TokenSet(accessToken: 'stale', refreshToken: 'refresh-1'),
    ),
    refresher: refresher,
  );
  final api = ApiClient(
    manager: manager,
    baseUrl: 'https://api.example.com',
    adapter: server,
  );

  final responses = await Future.wait([
    api.dio.get<Object?>('/me'),
    api.dio.get<Object?>('/me'),
    api.dio.get<Object?>('/me'),
  ]);

  stdout.writeln(
    '${responses.length} responses, ${refresher.calls} refresh, '
    '${server.received.length} requests sent',
  );
  await manager.dispose();
}
```

- [ ] **Step 4: Run the test to see it pass; run the example**

Run: `cd packages/token_manager_dio && dart test test/recipes/replace_refresh_interceptor_test.dart`
Expected: PASS, 4 tests.

Run: `cd packages/token_manager_dio && dart run example/recipes/replace_refresh_interceptor.dart`
Expected: it exits with code 0 (it prints a short walk-through).

- [ ] **Step 5: Run the docs test to see it fail, then write the page**

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: FAIL: `every recipe example is included by a page of its package` names `packages/token_manager_dio/example/recipes/replace_refresh_interceptor.dart`.

Create `packages/token_manager_dio/doc/recipes/replace_refresh_interceptor.md` (create the folder first). The line `<!-- include: ... -->` stays as written; the script of this task expands it into a `dart` block:

````markdown
# Recipe: replace a hand-written Dio refresh interceptor

Swap an interceptor that refreshes in `onError` for `DioTokenInterceptor`, so
that any number of parallel 401 responses start exactly one refresh and each
rejected request is replayed once.

## The pattern to remove

An interceptor of this shape has two common faults. N parallel 401s call the
refresh N times, and a request that is rejected again after its retry can be
retried again, which loops. This sketch is not compiled and not part of the
package:

```dart
onError: (error, handler) async {
  if (error.response?.statusCode == 401) {
    final tokens = await refreshTokens(); // runs once per failed request
    error.requestOptions.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    handler.resolve(await dio.fetch(error.requestOptions));
    return;
  }
  handler.next(error);
},
```

## The code

Move the call to your token endpoint into a `TokenRefresher` (see
[sign in and store the tokens](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/recipes/login_and_set_tokens.md)),
then build the client with `ApiClient`. `StandInRefresher` and
`StandInServer` replace your endpoint and your API so the file runs without a
network.

<!-- include: example/recipes/replace_refresh_interceptor.dart -->

Run it with `dart run example/recipes/replace_refresh_interceptor.dart`. The
test `test/recipes/replace_refresh_interceptor_test.dart` checks every
behaviour below.

## What you get

- Three parallel requests with a stale token share one refresh, and each
  request is sent twice: once rejected, once replayed with the new token.
- A refresh that returns the very tokens that were rejected sends nothing a
  second time; the original error reaches the caller.
- A dead refresh token reaches the caller as a `DioException` whose `error` is
  `InvalidGrant`; the manager has signed the session out.

## Common mistakes

- **Leaving the old interceptor in place.** Two interceptors add two headers
  and refresh twice. Delete the old one and the fields that held the tokens.
- **Omitting `dio:`.** Without it a plain `Dio()` sends the replay, without your
  adapter, interceptors and timeouts. Pass the `Dio` the interceptor is added
  to.
- **Refreshing through the same `Dio`.** See
  [skip auth for the login and refresh endpoints](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_dio/doc/recipes/skip_auth_endpoints.md).
- **Replaying a request that is not safe to send twice.** Any HTTP method is
  replayed; make a non-idempotent call safe to repeat.
- **Expecting a stream body to be replayed.** It cannot be sent twice, so its
  original error is returned and no refresh is started.

## See also

- [Getting started](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_dio/doc/getting_started.md)
- [Migrating from 0.1](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_dio/doc/migration.md)
````

Expand the include and check:

```bash
python3 /tmp/assemble_recipe.py packages/token_manager_dio/doc/recipes/replace_refresh_interceptor.md
```

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: PASS (the page includes the file verbatim, has no relative link and no banned wording).

- [ ] **Step 6: Format, analyze, commit**

Run: `dart format packages && dart analyze packages/token_manager_dio packages/docs_check`
Expected: `0 changed` and `No issues found!`.

```bash
git add packages/token_manager_dio/example/recipes/replace_refresh_interceptor.dart packages/token_manager_dio/test/recipes/replace_refresh_interceptor_test.dart packages/token_manager_dio/doc/recipes/replace_refresh_interceptor.md
git commit -m "docs(token_manager_dio): add the Replace a hand-written refresh interceptor recipe" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

#### Recipe `skip_auth_endpoints` (Skip auth for the login and refresh endpoints)

Public names of the example (the test and the page use them): `BearerDelegate`, `TokenEndpointAnswer`, `DioTokenRefresher`, `SessionClients`, `StandInServer`.

- [ ] **Step 7: Write the test of `skip_auth_endpoints`**

Create `packages/token_manager_dio/test/recipes/skip_auth_endpoints_test.dart`:

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

import '../../example/recipes/skip_auth_endpoints.dart'
    show BearerDelegate, SessionClients, StandInServer, TokenEndpointAnswer;

void main() {
  // Assigned in setUp, which runs before every test.
  late StandInServer server;
  late SessionClients clients;

  setUp(() {
    server = StandInServer(lifetime: 5);
    clients = SessionClients(
      baseUrl: 'https://api.test',
      store: InMemoryTokenStore<TokenSet>(),
      adapter: server,
    );
  });

  tearDown(() => clients.dispose());

  test(
    'signIn works while signed out, because auth has no interceptor',
    () async {
      await clients.signIn('ada@example.com', 'secret');

      expect((await clients.manager.current())?.accessToken, 'access-1');
    },
  );

  test('a call on the interceptor Dio fails with NotAuthenticated before '
      'login', () async {
    await expectLater(
      clients.api.get<Object?>('/me'),
      throwsA(
        isA<DioException>().having(
          (error) => error.error,
          'error',
          isA<NotAuthenticated>(),
        ),
      ),
    );

    expect(server.paths, isEmpty);
  });

  test('the refresh request is sent without waiting for itself', () async {
    await clients.signIn('ada@example.com', 'secret');

    final response = await clients.api.get<Object?>('/me');

    expect(response.statusCode, 200);
    expect(server.refreshes, 1);
  });

  test('the refresh request carries no Authorization header', () async {
    await clients.signIn('ada@example.com', 'secret');

    await clients.api.get<Object?>('/me');

    expect(server.endpointAuthorizations, [null, null]);
  });

  test('mistake: a refresh sent through the interceptor Dio waits for '
      'itself', () async {
    final api = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = server;
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(
        TokenSet(
          accessToken: 'old',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(seconds: 5)),
        ),
      ),
      refresher: _RefreshThrough(api),
      info: const TokenSetInfo(),
    );
    addTearDown(manager.dispose);
    api.interceptors.add(
      DioTokenInterceptor<TokenSet>(
        manager: manager,
        delegate: const BearerDelegate(),
        dio: api,
      ),
    );

    await expectLater(
      api.get<Object?>('/me').timeout(const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()),
    );
  });
}

final class _RefreshThrough implements TokenRefresher<TokenSet> {
  const _RefreshThrough(this._dio);

  final Dio _dio;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    final response = await _dio.post<Object?>('/oauth/token');
    return const TokenEndpointAnswer().parse(response.data);
  }
}
```

- [ ] **Step 8: Run it to see it fail**

Run: `cd packages/token_manager_dio && dart test test/recipes/skip_auth_endpoints_test.dart`
Expected: FAIL to compile: the example `example/recipes/skip_auth_endpoints.dart` does not exist yet.

- [ ] **Step 9: Write the example**

Create `packages/token_manager_dio/example/recipes/skip_auth_endpoints.dart`. It is the code the page shows; it uses only the public API, and every stand-in is a public class so the page can name it.

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

/// Writes the access token into the `Authorization` header.
final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  /// Creates the delegate.
  const BearerDelegate();

  @override
  void applyTo(RequestOptions options, TokenSet tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
  }
}

/// Reads the answer of the token endpoint.
final class TokenEndpointAnswer {
  /// Creates the reader.
  const TokenEndpointAnswer();

  /// Returns the tokens in [body], or throws a [FormatException].
  TokenSet parse(Object? body) {
    return switch (body) {
      {
        'access_token': final String access,
        'refresh_token': final String refresh,
        'expires_in': final int seconds,
      } =>
        TokenSet(
          accessToken: access,
          refreshToken: refresh,
          expiresAt: DateTime.now().add(Duration(seconds: seconds)),
        ),
      _ => throw const FormatException('Unreadable token endpoint answer'),
    };
  }
}

/// Refreshes through [_authDio], which has no token interceptor.
final class DioTokenRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher that posts to `/oauth/token` with [_authDio].
  const DioTokenRefresher(this._authDio);

  final Dio _authDio;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    try {
      final response = await _authDio.post<Object?>(
        '/oauth/token',
        data: {
          'grant_type': 'refresh_token',
          'refresh_token': current.refreshToken,
        },
      );
      return const TokenEndpointAnswer().parse(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 400) {
        // The server rejected the refresh token for good.
        throw const InvalidGrant();
      }
      rethrow; // anything else, such as a timeout, is Transient
    }
  }
}

/// The two clients of an app: [auth] for the login and refresh endpoints,
/// [api] for everything else.
final class SessionClients {
  /// Creates both clients over [store]; [adapter] replaces the network.
  factory SessionClients({
    required String baseUrl,
    required TokenStore<TokenSet> store,
    HttpClientAdapter? adapter,
  }) {
    // No interceptor on this one: its requests never ask for tokens.
    final auth = Dio(BaseOptions(baseUrl: baseUrl));
    final api = Dio(BaseOptions(baseUrl: baseUrl));
    if (adapter != null) {
      auth.httpClientAdapter = adapter;
      api.httpClientAdapter = adapter;
    }
    final manager = TokenManager<TokenSet>.create(
      store: store,
      refresher: DioTokenRefresher(auth),
      info: const TokenSetInfo(),
    );
    api.interceptors.add(
      DioTokenInterceptor<TokenSet>(
        manager: manager,
        delegate: const BearerDelegate(),
        dio: api,
      ),
    );
    return SessionClients._(auth, api, manager);
  }

  const SessionClients._(this.auth, this.api, this.manager);

  /// Sends the login and the refresh; never carries tokens.
  final Dio auth;

  /// Sends every authorized call.
  final Dio api;

  /// The manager behind [api].
  final TokenManager<TokenSet> manager;

  /// Signs in through [auth] and stores the tokens.
  Future<void> signIn(String email, String password) async {
    final response = await auth.post<Object?>(
      '/oauth/token',
      data: {'grant_type': 'password', 'username': email, 'password': password},
    );
    await manager.setTokens(const TokenEndpointAnswer().parse(response.data));
  }

  /// Releases the manager.
  Future<void> dispose() => manager.dispose();
}

// ---- Stand-in for your server, so this file runs without a network.

/// Serves `/oauth/token` and `/me`; access tokens live [lifetime] seconds.
final class StandInServer implements HttpClientAdapter {
  /// Creates a server that issues tokens valid for [lifetime] seconds.
  StandInServer({this.lifetime = 3600});

  /// The `expires_in` of an issued access token.
  final int lifetime;

  /// The path of every request, in arrival order.
  final List<String> paths = [];

  /// The `Authorization` header of every request to `/oauth/token`.
  final List<Object?> endpointAuthorizations = [];

  /// How many refreshes reached the token endpoint.
  int refreshes = 0;

  String _valid = 'access-1';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    if (options.path == '/oauth/token') {
      endpointAuthorizations.add(options.headers['Authorization']);
      final body = await requestStream?.toList() ?? const <Uint8List>[];
      return _issue(utf8.decode(body.expand((chunk) => chunk).toList()));
    }
    final isAccepted = options.headers['Authorization'] == 'Bearer $_valid';
    return _json(isAccepted ? 200 : 401, isAccepted ? {'me': 'ada'} : {});
  }

  ResponseBody _issue(String request) {
    if (request.contains('refresh_token')) {
      refreshes++;
      _valid = 'access-${refreshes + 1}';
    }
    return _json(200, {
      'access_token': _valid,
      'refresh_token': 'refresh-${refreshes + 1}',
      'expires_in': lifetime,
    });
  }

  ResponseBody _json(int status, Map<String, Object?> body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> main() async {
  final server = StandInServer(lifetime: 5);
  final clients = SessionClients(
    baseUrl: 'https://api.example.com',
    store: InMemoryTokenStore<TokenSet>(),
    adapter: server,
  );

  await clients.signIn('ada@example.com', 'correct horse');
  final response = await clients.api.get<Object?>('/me');

  stdout.writeln(
    '${response.statusCode} after ${server.refreshes} refresh; '
    'requests: ${server.paths}',
  );
  await clients.dispose();
}
```

- [ ] **Step 10: Run the test to see it pass; run the example**

Run: `cd packages/token_manager_dio && dart test test/recipes/skip_auth_endpoints_test.dart`
Expected: PASS, 5 tests.

Run: `cd packages/token_manager_dio && dart run example/recipes/skip_auth_endpoints.dart`
Expected: it exits with code 0 (it prints a short walk-through).

- [ ] **Step 11: Run the docs test to see it fail, then write the page**

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: FAIL: `every recipe example is included by a page of its package` names `packages/token_manager_dio/example/recipes/skip_auth_endpoints.dart`.

Create `packages/token_manager_dio/doc/recipes/skip_auth_endpoints.md` (create the folder first). The line `<!-- include: ... -->` stays as written; the script of this task expands it into a `dart` block:

```markdown
# Recipe: skip auth for the login and refresh endpoints

Send the login and the refresh request without tokens by giving them a
`Dio` that has no `DioTokenInterceptor`. Use this whenever the token endpoint
lives on the same server as your API.

## The code

`SessionClients` owns two clients: `auth` (no interceptor) sends the login and
the refresh through `DioTokenRefresher`; `api` (with the interceptor) sends
everything else. `StandInServer` replaces your server.

<!-- include: example/recipes/skip_auth_endpoints.dart -->

Run it with `dart run example/recipes/skip_auth_endpoints.dart`. The test
`test/recipes/skip_auth_endpoints_test.dart` checks every behaviour below.

## What you get

- `signIn` works while signed out, because `auth` never asks the manager for
  tokens.
- The refresh request carries no `Authorization` header and is sent once.
- A call on `api` while signed out fails with a `DioException` whose `error` is
  `NotAuthenticated`, and nothing is sent.
- A 400 from the token endpoint becomes `InvalidGrant` (the session ends); any
  other failure, such as a timeout, is transient and keeps the session.

## Common mistakes

- **Logging in through `api`.** The interceptor asks the manager for tokens
  before it sends, so a login while signed out fails with `NotAuthenticated`.
- **Refreshing through `api`.** The manager is waiting for the refresh, and a
  request on `api` waits for the manager: the call never completes (the test
  `mistake: a refresh sent through the interceptor Dio waits for itself` pins
  this).
- **Giving the two clients different adapters.** Share the adapter, proxy and
  certificate settings, or the login and the API behave differently.
- **Treating every error as `InvalidGrant`.** Only a rejection the server means
  for good ends the session. If your server uses another status for an invalid
  grant, change the `400` check.

## See also

- [Replace a hand-written refresh interceptor](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_dio/doc/recipes/replace_refresh_interceptor.md)
- [Getting started](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_dio/doc/getting_started.md)
```

Expand the include and check:

```bash
python3 /tmp/assemble_recipe.py packages/token_manager_dio/doc/recipes/skip_auth_endpoints.md
```

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: PASS (the page includes the file verbatim, has no relative link and no banned wording).

- [ ] **Step 12: Format, analyze, commit**

Run: `dart format packages && dart analyze packages/token_manager_dio packages/docs_check`
Expected: `0 changed` and `No issues found!`.

```bash
git add packages/token_manager_dio/example/recipes/skip_auth_endpoints.dart packages/token_manager_dio/test/recipes/skip_auth_endpoints_test.dart packages/token_manager_dio/doc/recipes/skip_auth_endpoints.md
git commit -m "docs(token_manager_dio): add the Skip auth for the login and refresh endpoints recipe" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 13: List the recipes in the token_manager_dio README**

Edit `packages/token_manager_dio/README.md`: add the table-of-contents entry and the section before `## Reference`.

Edit 1. Replace

```markdown
- [Reference](#reference)
```

with

```markdown
- [Recipes](#recipes)
- [Reference](#reference)
```

Edit 2. Replace

```markdown

## Reference
```

with

```markdown

## Recipes

Each recipe is one page with complete code that is compiled and tested in this repository.

- [Replace a hand-written refresh interceptor](doc/recipes/replace_refresh_interceptor.md)
- [Skip auth for the login and refresh endpoints](doc/recipes/skip_auth_endpoints.md)

## Reference
```

Run: `cd packages/docs_check && dart test test/readme_test.dart`
Expected: PASS.

```bash
git add packages/token_manager_dio/README.md
git commit -m "docs(token_manager_dio): list the recipes in the README" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

### Task 5: package:http recipe

**Files:**
- Create: `packages/token_manager_http/example/recipes/authorized_client.dart`, `packages/token_manager_http/test/recipes/authorized_client_test.dart`, `packages/token_manager_http/doc/recipes/authorized_client.md`
- Modify: `packages/token_manager_http/README.md`

**Interfaces:**
- Consumes: the recipe procedure and `/tmp/assemble_recipe.py` (Task 3); `packages/docs_check/test/recipe_pages_test.dart` (Task 3).
- Produces: the public classes listed under each recipe; later tasks do not depend on them.

Note: the stand-in server is a `MockClient` from `package:http/testing.dart`, which is part of `http`, so the recipe needs no new dependency.

#### Recipe `authorized_client` (An authorized `http.Client`)

Public names of the example (the test and the page use them): `TokenEndpointAnswer`, `HttpRefresher`, `AuthorizedHttp`, `StandInServer`.

- [ ] **Step 1: Write the test of `authorized_client`**

Create `packages/token_manager_http/test/recipes/authorized_client_test.dart`:

```dart
import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/authorized_client.dart'
    show AuthorizedHttp, StandInServer;

void main() {
  final me = Uri.parse('https://api.test/me');
  // Assigned in setUp, which runs before every test.
  late StandInServer server;
  late AuthorizedHttp http;

  setUp(() {
    server = StandInServer();
    http = AuthorizedHttp(
      transport: server.client,
      origin: Uri.parse('https://api.test'),
    );
  });

  tearDown(() => http.dispose());

  test('signIn stores the tokens without asking the manager for any', () async {
    await http.signIn('ada@example.com', 'secret');

    expect((await http.manager.current())?.accessToken, 'access-1');
  });

  test('a signed-in call carries the bearer header', () async {
    await http.signIn('ada@example.com', 'secret');

    final response = await http.client.get(me);

    expect(response.statusCode, 200);
    expect(server.received, ['Bearer access-1']);
  });

  test('a rejected token is refreshed and the call replayed once', () async {
    await http.signIn('ada@example.com', 'secret');
    server.revokeAccessToken();

    final response = await http.client.get(me);

    expect(response.statusCode, 200);
    expect(server.refreshes, 1);
    expect(server.received, ['Bearer access-1', 'Bearer access-2']);
  });

  test('parallel rejected calls share one refresh', () async {
    await http.signIn('ada@example.com', 'secret');
    server.revokeAccessToken();

    final responses = await Future.wait([
      http.client.get(me),
      http.client.get(me),
      http.client.get(me),
    ]);

    expect(responses.map((response) => response.statusCode), [200, 200, 200]);
    expect(server.refreshes, 1);
  });

  test('a call while signed out fails with NotAuthenticated', () async {
    await expectLater(
      http.client.get(me),
      throwsA(isA<NotAuthenticated>()),
    );

    expect(server.received, isEmpty);
  });

  test('a call after close fails with ClientException', () async {
    await http.signIn('ada@example.com', 'secret');
    http.client.close();

    await expectLater(http.client.get(me), throwsA(isA<ClientException>()));
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/token_manager_http && dart test test/recipes/authorized_client_test.dart`
Expected: FAIL to compile: the example `example/recipes/authorized_client.dart` does not exist yet.

- [ ] **Step 3: Write the example**

Create `packages/token_manager_http/example/recipes/authorized_client.dart`. It is the code the page shows; it uses only the public API, and every stand-in is a public class so the page can name it.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

/// Reads the answer of the token endpoint.
final class TokenEndpointAnswer {
  /// Creates the reader.
  const TokenEndpointAnswer();

  /// Returns the tokens in [body], or throws a [FormatException].
  TokenSet parse(String body) {
    return switch (jsonDecode(body)) {
      {
        'access_token': final String access,
        'refresh_token': final String refresh,
        'expires_in': final int seconds,
      } =>
        TokenSet(
          accessToken: access,
          refreshToken: refresh,
          expiresAt: DateTime.now().add(Duration(seconds: seconds)),
        ),
      _ => throw const FormatException('Unreadable token endpoint answer'),
    };
  }
}

/// Refreshes with a plain [Client], which never asks the manager for tokens.
final class HttpRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher that posts to [endpoint] with [client].
  const HttpRefresher({required Client client, required Uri endpoint})
    : _client = client,
      _endpoint = endpoint;

  final Client _client;
  final Uri _endpoint;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    final response = await _client.post(
      _endpoint,
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': current.refreshToken ?? '',
      },
    );
    return switch (response.statusCode) {
      200 => const TokenEndpointAnswer().parse(response.body),
      // The server rejected the refresh token for good.
      400 => throw const InvalidGrant(),
      // Anything else may go away: the session stays.
      final int status => throw Transient(status),
    };
  }
}

/// An authorized [Client] and the manager behind it.
final class AuthorizedHttp {
  /// Creates the client over [transport]; [store] defaults to memory.
  factory AuthorizedHttp({
    required Client transport,
    required Uri origin,
    TokenStore<TokenSet>? store,
  }) {
    final tokenUri = origin.resolve(_tokenPath);
    final manager = TokenManager<TokenSet>.create(
      store: store ?? InMemoryTokenStore<TokenSet>(),
      refresher: HttpRefresher(client: transport, endpoint: tokenUri),
      info: const TokenSetInfo(),
    );
    final client = HttpTokenClient<TokenSet>(
      manager: manager,
      inner: transport,
      // The sign-in and the refresh run before tokens exist or while the
      // manager is refreshing: they must not ask it for tokens.
      shouldAuthorize: (request) => request.url.path != _tokenPath,
    );
    return AuthorizedHttp._(manager, client, tokenUri);
  }

  const AuthorizedHttp._(this.manager, this.client, this._tokenUri);

  static const String _tokenPath = '/oauth/token';

  /// The manager behind [client].
  final TokenManager<TokenSet> manager;

  /// The client to use for every call to your API.
  final Client client;

  final Uri _tokenUri;

  /// Signs in and stores the tokens.
  Future<void> signIn(String email, String password) async {
    final response = await client.post(
      _tokenUri,
      body: {
        'grant_type': 'password',
        'username': email,
        'password': password,
      },
    );
    await manager.setTokens(
      const TokenEndpointAnswer().parse(response.body),
    );
  }

  /// Closes the client and releases the manager.
  Future<void> dispose() async {
    client.close();
    await manager.dispose();
  }
}

// ---- Stand-in for your server, so this file runs without a network.

/// Serves `/oauth/token` and `/me`; access tokens live [lifetime] seconds.
final class StandInServer {
  /// Creates a server that issues tokens valid for [lifetime] seconds.
  StandInServer({this.lifetime = 3600});

  /// The `expires_in` of an issued access token.
  final int lifetime;

  /// How many refreshes reached the token endpoint.
  int refreshes = 0;

  /// The `Authorization` header of every request to `/me`.
  final List<String?> received = [];

  String _valid = 'access-1';

  /// The transport to pass to [AuthorizedHttp].
  Client get client => MockClient(_handle);

  /// Makes the access token in use stale, like an early revocation.
  void revokeAccessToken() => _valid = 'revoked';

  Future<Response> _handle(Request request) async {
    if (request.url.path == '/oauth/token') {
      return _issue(request.bodyFields);
    }
    final authorization = request.headers['authorization'];
    received.add(authorization);
    if (authorization != 'Bearer $_valid') {
      return Response('expired', 401);
    }
    return Response(jsonEncode({'me': 'ada'}), 200);
  }

  Response _issue(Map<String, String> form) {
    if (form['grant_type'] == 'refresh_token') {
      refreshes++;
      _valid = 'access-${refreshes + 1}';
    }
    return Response(
      jsonEncode({
        'access_token': _valid,
        'refresh_token': 'refresh-${refreshes + 1}',
        'expires_in': lifetime,
      }),
      200,
    );
  }
}

Future<void> main() async {
  final server = StandInServer();
  final http = AuthorizedHttp(
    transport: server.client,
    origin: Uri.parse('https://api.example.com'),
  );

  await http.signIn('ada@example.com', 'correct horse');
  server.revokeAccessToken();
  final response = await http.client.get(
    Uri.parse('https://api.example.com/me'),
  );

  stdout.writeln(
    '${response.statusCode} after ${server.refreshes} refresh: '
    '${response.body}',
  );
  await http.dispose();
}
```

- [ ] **Step 4: Run the test to see it pass; run the example**

Run: `cd packages/token_manager_http && dart test test/recipes/authorized_client_test.dart`
Expected: PASS, 6 tests.

Run: `cd packages/token_manager_http && dart run example/recipes/authorized_client.dart`
Expected: it exits with code 0 (it prints a short walk-through).

- [ ] **Step 5: Run the docs test to see it fail, then write the page**

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: FAIL: `every recipe example is included by a page of its package` names `packages/token_manager_http/example/recipes/authorized_client.dart`.

Create `packages/token_manager_http/doc/recipes/authorized_client.md` (create the folder first). The line `<!-- include: ... -->` stays as written; the script of this task expands it into a `dart` block:

```markdown
# Recipe: an authorized http.Client

Give your app one `http.Client` that attaches the access token, refreshes once
when the server answers 401 and replays the request. Use this for code written
against `package:http`.

## The code

`AuthorizedHttp` builds the manager and an `HttpTokenClient` over one
`transport`. The refresher and the sign-in use the token endpoint, which
`shouldAuthorize` excludes. `StandInServer` is a `MockClient` that replaces
your server.

<!-- include: example/recipes/authorized_client.dart -->

Run it with `dart run example/recipes/authorized_client.dart`. The test
`test/recipes/authorized_client_test.dart` checks every behaviour below.

## What you get

- A signed-in call carries `Authorization: Bearer <accessToken>`.
- A call the server rejects is refreshed once and sent again once; parallel
  rejected calls share one refresh.
- The sign-in goes through the same client without tokens, because
  `shouldAuthorize` returns `false` for the token endpoint.
- A call while signed out fails with `NotAuthenticated` and sends nothing.
- A call after `close()` fails with a `ClientException`.

## Common mistakes

- **Sending the refresh through the authorized client.** The manager is waiting
  for the refresh, and a request through the client asks the manager for
  tokens. Give `HttpRefresher` the plain `transport`.
- **Forgetting `shouldAuthorize` for the login.** Without it a request sent
  while signed out fails with `NotAuthenticated`.
- **Expecting every request to be replayed.** Only a `Request` or an
  `AbortableRequest` is; a `StreamedRequest` or a `MultipartRequest` is sent once
  and its 401 is returned.
- **Expecting `close()` to dispose the manager.** It closes the inner client
  only; dispose the manager yourself.
- **Using a token type other than `TokenSet` without `headers`.** The client
  throws an `ArgumentError`; pass `headers: (tokens) => {...}`.

## See also

- [Getting started](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_http/doc/getting_started.md)
- [What is replayed](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_http/doc/replay.md)
- [Testing](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_http/doc/testing.md)
```

Expand the include and check:

```bash
python3 /tmp/assemble_recipe.py packages/token_manager_http/doc/recipes/authorized_client.md
```

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: PASS (the page includes the file verbatim, has no relative link and no banned wording).

- [ ] **Step 6: Format, analyze, commit**

Run: `dart format packages && dart analyze packages/token_manager_http packages/docs_check`
Expected: `0 changed` and `No issues found!`.

```bash
git add packages/token_manager_http/example/recipes/authorized_client.dart packages/token_manager_http/test/recipes/authorized_client_test.dart packages/token_manager_http/doc/recipes/authorized_client.md
git commit -m "docs(token_manager_http): add the An authorized http.Client recipe" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: List the recipes in the token_manager_http README**

Edit `packages/token_manager_http/README.md`: add the table-of-contents entry and the section before `## Reference`.

Edit 1. Replace

```markdown
- [Reference](#reference)
```

with

```markdown
- [Recipes](#recipes)
- [Reference](#reference)
```

Edit 2. Replace

```markdown

## Reference
```

with

```markdown

## Recipes

Each recipe is one page with complete code that is compiled and tested in this repository.

- [An authorized `http.Client`](doc/recipes/authorized_client.md)

## Reference
```

Run: `cd packages/docs_check && dart test test/readme_test.dart`
Expected: PASS.

```bash
git add packages/token_manager_http/README.md
git commit -m "docs(token_manager_http): list the recipes in the README" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

### Task 6: gRPC recipe

**Files:**
- Create: `packages/token_manager_grpc/example/recipes/unary_and_streaming.dart`, `packages/token_manager_grpc/test/recipes/unary_and_streaming_test.dart`, `packages/token_manager_grpc/doc/recipes/unary_and_streaming.md`
- Modify: `packages/token_manager_grpc/README.md`

**Interfaces:**
- Consumes: the recipe procedure and `/tmp/assemble_recipe.py` (Task 3); `packages/docs_check/test/recipe_pages_test.dart` (Task 3).
- Produces: the public classes listed under each recipe; later tasks do not depend on them.

Note: the test imports the fakes `FakeUnaryInvoker`, `FakeStreamInvoker` and `GrpcFixture` from `packages/token_manager_grpc/test/helpers/` (they exist on `main`). If a helper was renamed by `chore/patch-releases`, use the new name; do not copy a helper into the recipe. The example builds `GrpcSession` with a factory and a private constructor, not `late final`, because `CLAUDE.md` requires a comment for every `late`.

#### Recipe `unary_and_streaming` (Unary and streaming calls with one refresh)

Public names of the example (the test and the page use them): `TokenExchange`, `BearerDelegate`, `ExchangeRefresher`, `GrpcSession`, `StandInExchange`.

- [ ] **Step 1: Write the test of `unary_and_streaming`**

Create `packages/token_manager_grpc/test/recipes/unary_and_streaming_test.dart`:

```dart
import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/unary_and_streaming.dart'
    show GrpcSession, StandInExchange, TokenExchange;
import '../helpers/fake_stream_invoker.dart';
import '../helpers/fake_unary_invoker.dart';
import '../helpers/grpc_fixture.dart';

final class _RejectingExchange implements TokenExchange {
  const _RejectingExchange();

  @override
  Future<TokenSet> exchange(String refreshToken) async {
    throw const grpc.GrpcError.unauthenticated();
  }
}

void main() {
  const unauthenticated = grpc.GrpcError.unauthenticated();
  // Assigned in setUp, which runs before every test.
  late StandInExchange exchange;
  late GrpcSession session;

  Future<GrpcSession> signedIn(TokenExchange exchange) async {
    final session = GrpcSession(
      channel: grpc.ClientChannel('localhost', port: 1),
      exchange: exchange,
    );
    await session.manager.setTokens(
      const TokenSet(accessToken: 'access-0', refreshToken: 'refresh'),
    );
    addTearDown(session.close);
    return session;
  }

  setUp(() async {
    exchange = StandInExchange();
    session = await signedIn(exchange);
  });

  grpc.ResponseFuture<String> unary(FakeUnaryInvoker<String, String> invoker) =>
      session.interceptor.interceptUnary<String, String>(
        GrpcFixture.method,
        'ping',
        grpc.CallOptions(),
        invoker.invoke,
      );

  test('two unary calls rejected together share one refresh', () async {
    final invoker = FakeUnaryInvoker<String, String>();
    final first = unary(invoker);
    final second = unary(invoker);
    await GrpcFixture.settle();

    invoker.calls[0].fail(unauthenticated);
    invoker.calls[1].fail(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[2].succeed('pong');
    invoker.calls[3].succeed('pong');

    expect(await Future.wait([first, second]), ['pong', 'pong']);
    expect(exchange.calls, 1);
    expect(invoker.calls.map((call) => call.authorization), [
      'Bearer access-0',
      'Bearer access-0',
      'Bearer access-1',
      'Bearer access-1',
    ]);
  });

  test('a unary call is replayed only once', () async {
    final invoker = FakeUnaryInvoker<String, String>();
    final response = unary(invoker);
    final failure = expectLater(response, throwsA(isA<grpc.GrpcError>()));
    await GrpcFixture.settle();

    invoker.calls[0].fail(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].fail(unauthenticated);

    await failure;
    expect(invoker.calls, hasLength(2));
  });

  test('a streaming call is reopened once before its first response', () async {
    final invoker = FakeStreamInvoker<String, String>();
    addTearDown(invoker.closeAll);
    final received = <String>[];
    final subscription = session.interceptor
        .interceptStreaming<String, String>(
          GrpcFixture.method,
          Stream<String>.value('ping'),
          grpc.CallOptions(),
          invoker.invoke,
        )
        .listen(received.add);
    await GrpcFixture.settle();

    invoker.calls[0].responses.addError(unauthenticated);
    await GrpcFixture.settle();
    invoker.calls[1].responses.add('a');
    await GrpcFixture.settle();

    expect(invoker.calls.map((call) => call.authorization), [
      'Bearer access-0',
      'Bearer access-1',
    ]);
    expect(received, ['a']);
    expect(invoker.calls[1].sent, ['ping']);
    await subscription.cancel();
  });

  test('a rejected refresh token fails the call with InvalidGrant', () async {
    session = await signedIn(const _RejectingExchange());
    final invoker = FakeUnaryInvoker<String, String>();
    final response = unary(invoker);
    final failure = expectLater(response, throwsA(isA<InvalidGrant>()));
    await GrpcFixture.settle();

    invoker.calls[0].fail(unauthenticated);

    await failure;
    expect(await session.manager.current(), isNull);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/token_manager_grpc && dart test test/recipes/unary_and_streaming_test.dart`
Expected: FAIL to compile: the example `example/recipes/unary_and_streaming.dart` does not exist yet.

- [ ] **Step 3: Write the example**

Create `packages/token_manager_grpc/example/recipes/unary_and_streaming.dart`. It is the code the page shows; it uses only the public API, and every stand-in is a public class so the page can name it.

```dart
import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

/// Exchanges a refresh token for new tokens; implement it with a client of
/// your auth service that has no token interceptor.
abstract interface class TokenExchange {
  /// Returns the tokens issued for [refreshToken].
  Future<TokenSet> exchange(String refreshToken);
}

/// Sends the access token as `authorization: Bearer <token>` metadata.
final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  /// Creates the delegate.
  const BearerDelegate();

  @override
  grpc.CallOptions buildCallOptions(TokenSet? tokens) => grpc.CallOptions(
    metadata: {
      if (tokens != null) 'authorization': 'Bearer ${tokens.accessToken}',
    },
  );
}

/// Refreshes through [TokenExchange].
final class ExchangeRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher over [_exchange].
  const ExchangeRefresher(this._exchange);

  final TokenExchange _exchange;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    final refreshToken = current.refreshToken;
    if (refreshToken == null) {
      throw const InvalidGrant();
    }
    try {
      return await _exchange.exchange(refreshToken);
    } on grpc.GrpcError catch (error) {
      if (error.code == grpc.StatusCode.unauthenticated) {
        // The auth service rejected the refresh token for good.
        throw const InvalidGrant();
      }
      rethrow; // anything else, such as UNAVAILABLE, is Transient
    }
  }
}

/// One channel, one manager and the interceptor that joins them.
final class GrpcSession {
  /// Creates a session; [store] defaults to memory.
  factory GrpcSession({
    required grpc.ClientChannel channel,
    required TokenExchange exchange,
    TokenStore<TokenSet>? store,
  }) {
    final manager = TokenManager<TokenSet>.create(
      store: store ?? InMemoryTokenStore<TokenSet>(),
      refresher: ExchangeRefresher(exchange),
      info: const TokenSetInfo(),
    );
    final interceptor = GrpcTokenInterceptor<TokenSet>(
      manager: manager,
      delegate: const BearerDelegate(),
    );
    return GrpcSession._(channel, manager, interceptor);
  }

  const GrpcSession._(this.channel, this.manager, this.interceptor);

  /// The channel every client of the app shares.
  final grpc.ClientChannel channel;

  /// The manager behind [interceptor]; call `setTokens` after sign-in.
  final TokenManager<TokenSet> manager;

  /// Pass it to every generated client, for example
  /// `GreeterClient(channel, interceptors: [session.interceptor])`.
  ///
  /// Unary calls are replayed once after UNAUTHENTICATED. A streaming call is
  /// reopened once, only before its first response and only when its request
  /// stream ended after at most one request.
  final GrpcTokenInterceptor<TokenSet> interceptor;

  /// Shuts the channel down and releases the manager.
  Future<void> close() async {
    await channel.shutdown();
    await manager.dispose();
  }
}

// ---- Stand-in for your auth service, so this file runs without a server.

/// An auth service that issues `access-<n>` on its n-th exchange.
final class StandInExchange implements TokenExchange {
  /// How many exchanges reached the service.
  int calls = 0;

  @override
  Future<TokenSet> exchange(String refreshToken) async {
    calls++;
    return TokenSet(accessToken: 'access-$calls', refreshToken: 'refresh');
  }
}

Future<void> main() async {
  final session = GrpcSession(
    channel: grpc.ClientChannel(
      'localhost',
      port: 50051,
      options: const grpc.ChannelOptions(
        credentials: grpc.ChannelCredentials.insecure(),
      ),
    ),
    exchange: StandInExchange(),
  );
  await session.manager.setTokens(
    const TokenSet(accessToken: 'access-0', refreshToken: 'refresh'),
  );

  // Nothing connects until the first call.
  final client = grpc.Client(
    session.channel,
    interceptors: [session.interceptor],
  );
  stdout.writeln('Client ready: ${client.runtimeType}');

  await session.close();
}
```

- [ ] **Step 4: Run the test to see it pass; run the example**

Run: `cd packages/token_manager_grpc && dart test test/recipes/unary_and_streaming_test.dart`
Expected: PASS, 4 tests.

Run: `cd packages/token_manager_grpc && dart run example/recipes/unary_and_streaming.dart`
Expected: it exits with code 0 (it prints a short walk-through).

- [ ] **Step 5: Run the docs test to see it fail, then write the page**

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: FAIL: `every recipe example is included by a page of its package` names `packages/token_manager_grpc/example/recipes/unary_and_streaming.dart`.

Create `packages/token_manager_grpc/doc/recipes/unary_and_streaming.md` (create the folder first). The line `<!-- include: ... -->` stays as written; the script of this task expands it into a `dart` block:

```markdown
# Recipe: unary and streaming gRPC calls with one refresh

Attach a bearer token to every gRPC call and refresh once when the server
answers `UNAUTHENTICATED`, for unary and streaming calls alike.

## The code

`GrpcSession` joins a channel, a manager and a `GrpcTokenInterceptor`. Pass its
`interceptor` to every client: `GreeterClient(session.channel, interceptors:
[session.interceptor])` for a generated client. `TokenExchange` is your auth
service client; it must not use the interceptor. `StandInExchange` replaces it.

<!-- include: example/recipes/unary_and_streaming.dart -->

Run it with `dart run example/recipes/unary_and_streaming.dart`; it builds the
client and opens no connection. The test
`test/recipes/unary_and_streaming_test.dart` checks every behaviour below with
the fake calls of the package's own tests.

## What you get

- Two unary calls rejected together share one refresh, and each is sent again
  once with the new token.
- A unary call is replayed once; a second `UNAUTHENTICATED` reaches the caller.
- A streaming call is reopened once, only before its first response and only
  when its request stream ended after at most one request, so a response is
  never delivered twice.
- A dead refresh token fails the call with `InvalidGrant` and signs the session
  out.

## Common mistakes

- **Exchanging the refresh token with an intercepted client.** The manager is
  waiting for the exchange, and an intercepted call waits for the manager. Use
  a client of the auth service without the interceptor.
- **Expecting a long client-streaming call to be replayed.** A call that sent
  more than one request, or already got a response, is not reopened; the error
  reaches the caller and the rejected tokens are reported so the next call
  gets new ones.
- **Mapping every error to `InvalidGrant`.** Only `UNAUTHENTICATED` from the auth
  service means the refresh token is dead; `UNAVAILABLE` is transient.
- **Relying on `PERMISSION_DENIED` to refresh.** The default `shouldRefresh`
  accepts `UNAUTHENTICATED` only; override it in the delegate if your server
  differs.
- **Replaying a call that is not safe to repeat.** A unary call may reach the
  server twice; make it idempotent.

## See also

- [Getting started](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_grpc/doc/getting_started.md)
- [README: client-streaming and bidirectional calls](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_grpc/README.md#client-streaming-and-bidirectional-calls)
```

Expand the include and check:

```bash
python3 /tmp/assemble_recipe.py packages/token_manager_grpc/doc/recipes/unary_and_streaming.md
```

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: PASS (the page includes the file verbatim, has no relative link and no banned wording).

- [ ] **Step 6: Format, analyze, commit**

Run: `dart format packages && dart analyze packages/token_manager_grpc packages/docs_check`
Expected: `0 changed` and `No issues found!`.

```bash
git add packages/token_manager_grpc/example/recipes/unary_and_streaming.dart packages/token_manager_grpc/test/recipes/unary_and_streaming_test.dart packages/token_manager_grpc/doc/recipes/unary_and_streaming.md
git commit -m "docs(token_manager_grpc): add the Unary and streaming calls with one refresh recipe" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: List the recipes in the token_manager_grpc README**

Edit `packages/token_manager_grpc/README.md`: add the table-of-contents entry and the section before `## Reference`.

Edit 1. Replace

```markdown
- [Reference](#reference)
```

with

```markdown
- [Recipes](#recipes)
- [Reference](#reference)
```

Edit 2. Replace

```markdown

## Reference
```

with

```markdown

## Recipes

Each recipe is one page with complete code that is compiled and tested in this repository.

- [Unary and streaming calls with one refresh](doc/recipes/unary_and_streaming.md)

## Reference
```

Run: `cd packages/docs_check && dart test test/readme_test.dart`
Expected: PASS.

```bash
git add packages/token_manager_grpc/README.md
git commit -m "docs(token_manager_grpc): list the recipes in the README" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

### Task 7: GraphQL recipe

**Files:**
- Create: `packages/token_manager_gql/example/recipes/queries_and_subscriptions.dart`, `packages/token_manager_gql/test/recipes/queries_and_subscriptions_test.dart`, `packages/token_manager_gql/doc/recipes/queries_and_subscriptions.md`
- Modify: `packages/token_manager_gql/README.md`

**Interfaces:**
- Consumes: the recipe procedure and `/tmp/assemble_recipe.py` (Task 3); `packages/docs_check/test/recipe_pages_test.dart` (Task 3).
- Produces: the public classes listed under each recipe; later tasks do not depend on them.

Note: the example cannot import `package:graphql` (not a dependency of this package). It declares `typedef SocketLinkBuilder`, the one place where the page tells the reader to plug in their `WebSocketLink`, and `StandInServer extends Link` for the tests. The test variables are named `payload` and `connectionLost` so that the builder parameters do not shadow them.

#### Recipe `queries_and_subscriptions` (Queries and WebSocket subscriptions)

Public names of the example (the test and the page use them): `SocketLinkBuilder`, `MutationRefresher`, `TokenPayload`, `AuthorizedLinks`, `StandInServer`.

- [ ] **Step 1: Write the test of `queries_and_subscriptions`**

Create `packages/token_manager_gql/test/recipes/queries_and_subscriptions_test.dart`:

```dart
import 'package:gql/language.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/queries_and_subscriptions.dart'
    show AuthorizedLinks, StandInServer;

void main() {
  // Assigned in setUp, which runs before every test.
  late StandInServer server;
  late AuthorizedLinks links;
  late Future<Map<String, Object?>> Function() payload;
  late Future<Duration?> Function(int? code, String? reason) connectionLost;
  late List<String> socketOperations;

  Request operation(String name, String document) => Request(
    operation: Operation(document: parseString(document), operationName: name),
  );

  Request query() => operation('Me', 'query Me { me }');

  setUp(() {
    server = StandInServer();
    socketOperations = [];
    links = AuthorizedLinks(
      httpLink: server,
      buildSocket: ({required initialPayload, required onConnectionLost}) {
        payload = initialPayload;
        connectionLost = onConnectionLost;
        return _RecordingLink(socketOperations);
      },
    );
  });

  tearDown(() => links.dispose());

  test('signIn works while signed out and stores the tokens', () async {
    await links.signIn('ada@example.com', 'secret');

    expect((await links.manager.current())?.accessToken, 'access-1');
  });

  test('a query while signed out fails with NotAuthenticated', () async {
    await expectLater(
      links.link.request(query()).first,
      throwsA(isA<NotAuthenticated>()),
    );

    expect(server.received, isEmpty);
  });

  test('a rejected query is refreshed and replayed once', () async {
    await links.signIn('ada@example.com', 'secret');
    server.revokeAccessToken();

    final response = await links.link.request(query()).first;

    expect(response.data, {'me': 'ada'});
    expect(server.refreshes, 1);
    expect(server.received, ['Bearer access-1', 'Bearer access-2']);
  });

  test('a subscription goes to the socket link, not the HTTP link', () async {
    await links.signIn('ada@example.com', 'secret');

    await links.link
        .request(operation('Ticks', 'subscription Ticks { tick }'))
        .first;

    expect(socketOperations, ['Ticks']);
    expect(server.received, isEmpty);
  });

  test('the socket payload carries the current access token', () async {
    await links.signIn('ada@example.com', 'secret');

    expect(await payload(), {'Authorization': 'Bearer access-1'});
  });

  test('an auth close code refreshes once and reconnects at once', () async {
    await links.signIn('ada@example.com', 'secret');
    await payload();

    final delay = await connectionLost(4401, 'Unauthorized');

    expect(delay, Duration.zero);
    expect(server.refreshes, 1);
    expect(await payload(), {'Authorization': 'Bearer access-2'});
  });

  test('another close code leaves the tokens alone', () async {
    await links.signIn('ada@example.com', 'secret');
    await payload();

    expect(await connectionLost(1006, null), isNull);
    expect(server.refreshes, 0);
  });
}

final class _RecordingLink extends Link {
  _RecordingLink(this._operations);

  final List<String> _operations;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final name = request.operation.operationName;
    if (name != null) {
      _operations.add(name);
    }
    return Stream.value(const Response(data: {'tick': 1}, response: {}));
  }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd packages/token_manager_gql && dart test test/recipes/queries_and_subscriptions_test.dart`
Expected: FAIL to compile: the example `example/recipes/queries_and_subscriptions.dart` does not exist yet.

- [ ] **Step 3: Write the example**

Create `packages/token_manager_gql/example/recipes/queries_and_subscriptions.dart`. It is the code the page shows; it uses only the public API, and every stand-in is a public class so the page can name it.

```dart
import 'dart:async';
import 'dart:io';

import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

/// Builds the WebSocket link of your GraphQL client from the two callbacks of
/// [TokenManagerSocketAuth].
///
/// In an app this is where you create your client's WebSocket link, passing
/// [initialPayload] and [onConnectionLost] to its config.
typedef SocketLinkBuilder =
    Link Function({
      required Future<Map<String, Object?>> Function() initialPayload,
      required Future<Duration?> Function(int? code, String? reason)
      onConnectionLost,
    });

/// Refreshes with a mutation sent through [_link], the HTTP link alone.
///
/// The link must not contain a [TokenManagerLink]: the refresh runs while the
/// manager waits for it.
final class MutationRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher that sends the refresh mutation through [_link].
  const MutationRefresher(this._link);

  final Link _link;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    final response = await _link
        .request(
          Request(
            operation: Operation(
              document: parseString(
                r'mutation Refresh($token: String!) { '
                r'refresh(refreshToken: $token) '
                '{ accessToken refreshToken } }',
              ),
              operationName: 'Refresh',
            ),
            variables: {'token': current.refreshToken},
          ),
        )
        .first;
    return const TokenPayload().parse(response.data, 'refresh');
  }
}

/// Reads the tokens a login or refresh mutation returns.
final class TokenPayload {
  /// Creates the reader.
  const TokenPayload();

  /// Returns the tokens under `data[field]`, or throws a [FormatException]
  /// (a rejected login arrives as GraphQL `errors` and has no `data`).
  TokenSet parse(Map<String, Object?>? data, String field) {
    return switch (data?[field]) {
      {
        'accessToken': final String access,
        'refreshToken': final String refresh,
      } =>
        TokenSet(
          accessToken: access,
          refreshToken: refresh,
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        ),
      _ => throw FormatException('No tokens in the "$field" answer'),
    };
  }
}

/// The links of an app: queries and mutations over HTTP, subscriptions over a
/// WebSocket, one session.
final class AuthorizedLinks {
  /// Creates the links.
  ///
  /// [httpLink] is your terminating HTTP link, for example `HttpLink(url)`;
  /// [buildSocket] creates the WebSocket link of your client.
  factory AuthorizedLinks({
    required Link httpLink,
    required SocketLinkBuilder buildSocket,
    TokenStore<TokenSet>? store,
  }) {
    final manager = TokenManager<TokenSet>.create(
      store: store ?? InMemoryTokenStore<TokenSet>(),
      refresher: MutationRefresher(httpLink),
      info: const TokenSetInfo(),
    );
    final socketAuth = TokenManagerSocketAuth<TokenSet>(
      manager: manager,
      payload: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    final link = Link.split(
      (request) =>
          request.operation.getOperationType() == OperationType.subscription,
      buildSocket(
        initialPayload: socketAuth.initialPayload,
        onConnectionLost: socketAuth.onConnectionLost,
      ),
      Link.from([
        // Add DedupeLink() first, as in the README, when you use it.
        TokenManagerLink<TokenSet>(
          manager: manager,
          headers: (tokens) => {
            'Authorization': 'Bearer ${tokens.accessToken}',
          },
        ),
        httpLink,
      ]),
    );
    return AuthorizedLinks._(manager, link);
  }

  const AuthorizedLinks._(this.manager, this.link);

  /// The manager behind the links.
  final TokenManager<TokenSet> manager;

  /// The link to give to your GraphQL client.
  final Link link;

  /// Signs in with a mutation that is sent without tokens.
  Future<void> signIn(String email, String password) async {
    final request = Request(
      operation: Operation(
        document: parseString(
          r'mutation Login($email: String!, $password: String!) { '
          r'login(email: $email, password: $password) '
          '{ accessToken refreshToken } }',
        ),
        operationName: 'Login',
      ),
      variables: {'email': email, 'password': password},
      // A login runs before tokens exist; without this entry the link would
      // fail it with NotAuthenticated.
      context: const Context().withEntry(const SkipAuthorization()),
    );
    final response = await link.request(request).first;
    await manager.setTokens(const TokenPayload().parse(response.data, 'login'));
  }

  /// Releases the manager.
  Future<void> dispose() => manager.dispose();
}

// ---- Stand-in for your server, so this file runs without a network.

/// Answers `Login`, `Refresh`, `Me` and `Ticks` like a GraphQL server that
/// accepts only its newest access token.
final class StandInServer extends Link {
  /// How many `Refresh` mutations reached the server.
  int refreshes = 0;

  /// The `Authorization` header of every `Me` query, in arrival order.
  final List<String?> received = [];

  String _valid = 'access-1';

  /// Makes the access token in use stale, like an early revocation.
  void revokeAccessToken() => _valid = 'revoked';

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final headers = request.context.entry<HttpLinkHeaders>()?.headers;
    return switch (request.operation.operationName) {
      'Login' => _tokens('login'),
      'Refresh' => _refresh(),
      'Ticks' => Stream.value(const Response(data: {'tick': 1}, response: {})),
      _ => _me(headers?['Authorization']),
    };
  }

  Stream<Response> _refresh() {
    refreshes++;
    _valid = 'access-${refreshes + 1}';
    return _tokens('refresh');
  }

  Stream<Response> _tokens(String field) {
    return Stream.value(
      Response(
        data: {
          field: {
            'accessToken': _valid,
            'refreshToken': 'refresh-${refreshes + 1}',
          },
        },
        response: const {},
      ),
    );
  }

  Stream<Response> _me(String? authorization) {
    received.add(authorization);
    if (authorization != 'Bearer $_valid') {
      return Stream.error(const ServerException(statusCode: 401));
    }
    return Stream.value(const Response(data: {'me': 'ada'}, response: {}));
  }
}

Future<void> main() async {
  final server = StandInServer();
  final links = AuthorizedLinks(
    httpLink: server,
    buildSocket: ({required initialPayload, required onConnectionLost}) =>
        server,
  );

  await links.signIn('ada@example.com', 'correct horse');
  server.revokeAccessToken();
  final response = await links.link
      .request(
        Request(
          operation: Operation(
            document: parseString('query Me { me }'),
            operationName: 'Me',
          ),
        ),
      )
      .first;

  stdout.writeln(
    'Data ${response.data} after ${server.refreshes} refresh; '
    'sent ${server.received}',
  );
  await links.dispose();
}
```

- [ ] **Step 4: Run the test to see it pass; run the example**

Run: `cd packages/token_manager_gql && dart test test/recipes/queries_and_subscriptions_test.dart`
Expected: PASS, 7 tests.

Run: `cd packages/token_manager_gql && dart run example/recipes/queries_and_subscriptions.dart`
Expected: it exits with code 0 (it prints a short walk-through).

- [ ] **Step 5: Run the docs test to see it fail, then write the page**

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: FAIL: `every recipe example is included by a page of its package` names `packages/token_manager_gql/example/recipes/queries_and_subscriptions.dart`.

Create `packages/token_manager_gql/doc/recipes/queries_and_subscriptions.md` (create the folder first). The line `<!-- include: ... -->` stays as written; the script of this task expands it into a `dart` block:

```markdown
# Recipe: GraphQL queries and WebSocket subscriptions

Authorize queries and mutations over HTTP with `TokenManagerLink`, and
subscriptions over a WebSocket with `TokenManagerSocketAuth`, from one manager.

## The code

`AuthorizedLinks` builds the manager and the combined `Link` for your client.
`httpLink` is your terminating link (for example `HttpLink(url)`). `buildSocket`
creates the WebSocket link of your client; in an app it passes
`initialPayload` and `onConnectionLost` to that client's socket config, as the
[subscriptions guide](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_gql/doc/subscriptions.md)
shows. The recipe depends only on `gql_link`, so it does not import a client.
`StandInServer` replaces your server.

<!-- include: example/recipes/queries_and_subscriptions.dart -->

Run it with `dart run example/recipes/queries_and_subscriptions.dart`. The test
`test/recipes/queries_and_subscriptions_test.dart` checks every behaviour below.

## What you get

- `signIn` runs without tokens because its request carries
  `SkipAuthorization`.
- A query sent while signed out fails with `NotAuthenticated` before it is sent.
- A query the server rejects (HTTP 401 or an `UNAUTHENTICATED` error) is
  refreshed once and replayed once.
- A subscription goes to the socket link; the socket payload carries the
  current access token.
- A close with the auth code (4401 by default) refreshes the tokens once and
  asks the client to reconnect at once; any other close leaves them alone.

## Common mistakes

- **Putting `TokenManagerLink` after the terminating link.** It must come before
  it, after `DedupeLink` when you use one.
- **Combining it with the client's own auth link.** Both set the header and the
  other cannot replay.
- **Refreshing through the full link.** The refresher sends its mutation through
  `httpLink` alone: the manager waits for the refresh, and a request on the
  full link waits for the manager.
- **Logging in without `SkipAuthorization`.** A login runs before tokens exist
  and would fail with `NotAuthenticated`.
- **Leaving the socket open after logout.** The app still has to close or
  dispose the WebSocket link when `states` emits `Unauthenticated`, and bound
  the reconnects after a refresh; see the subscriptions guide.
- **Using the wrong close code.** Set `authCloseCodes` to what your server sends.

## See also

- [Getting started](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_gql/doc/getting_started.md)
- [Auth failures](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_gql/doc/auth_failures.md)
- [Clients](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_gql/doc/clients.md)
```

Expand the include and check:

```bash
python3 /tmp/assemble_recipe.py packages/token_manager_gql/doc/recipes/queries_and_subscriptions.md
```

Run: `cd packages/docs_check && dart test test/recipe_pages_test.dart`
Expected: PASS (the page includes the file verbatim, has no relative link and no banned wording).

- [ ] **Step 6: Format, analyze, commit**

Run: `dart format packages && dart analyze packages/token_manager_gql packages/docs_check`
Expected: `0 changed` and `No issues found!`.

```bash
git add packages/token_manager_gql/example/recipes/queries_and_subscriptions.dart packages/token_manager_gql/test/recipes/queries_and_subscriptions_test.dart packages/token_manager_gql/doc/recipes/queries_and_subscriptions.md
git commit -m "docs(token_manager_gql): add the Queries and WebSocket subscriptions recipe" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: List the recipes in the token_manager_gql README**

Edit `packages/token_manager_gql/README.md`: add the table-of-contents entry and the section before `## Reference`.

Edit 1. Replace

```markdown
- [Reference](#reference)
```

with

```markdown
- [Recipes](#recipes)
- [Reference](#reference)
```

Edit 2. Replace

```markdown

## Reference
```

with

```markdown

## Recipes

Each recipe is one page with complete code that is compiled and tested in this repository.

- [Queries and WebSocket subscriptions](doc/recipes/queries_and_subscriptions.md)

## Reference
```

Run: `cd packages/docs_check && dart test test/readme_test.dart`
Expected: PASS.

```bash
git add packages/token_manager_gql/README.md
git commit -m "docs(token_manager_gql): list the recipes in the README" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

### Task 8: Recipe index, llms.txt and the link check

**Files:**
- Create: `docs/recipes.md`, `llms.txt`, `packages/docs_check/test/helpers/link_checker.dart`, `packages/docs_check/test/link_checker_test.dart`, `packages/docs_check/test/links_test.dart`
- Modify: `README.md` (repository root)

**Interfaces:**
- Consumes: `RepositoryDocs` (`checkedPages`, `llms`, `recipeIndex`, `recipePages`, `relativePath`), `MarkdownLinks` (Task 3).
- Produces: `LinkChecker(Directory root)` with `static const String blobPrefix` (`https://github.com/4akloon/dart_token_manager/blob/main/`) and `failuresIn(File page) -> List<String>`: a relative link is resolved from the page, a link under `blobPrefix` from the repository root, every other absolute link is skipped (no network), a `#anchor` must match a heading of the target Markdown file.

- [ ] **Step 1: Write the failing tests**

Create `packages/docs_check/test/link_checker_test.dart` (the checker itself, on a temporary tree):

```dart
import 'dart:io';

import 'package:test/test.dart';

import 'helpers/link_checker.dart';

void main() {
  // Assigned in setUp, which runs before every test.
  late Directory root;
  late LinkChecker checker;

  File write(String path, String text) {
    final file = File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    return file;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('link_checker_test');
    checker = LinkChecker(root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('a relative link to an existing file resolves', () {
    write('docs/b.md', '# B\n');
    final page = write('docs/a.md', '[b](b.md)\n');

    expect(checker.failuresIn(page), isEmpty);
  });

  test('a relative link to a missing file fails', () {
    final page = write('docs/a.md', '[b](missing.md)\n');

    expect(checker.failuresIn(page), hasLength(1));
  });

  test('an anchor must name a heading of the target', () {
    write('docs/b.md', '# Real heading\n');
    final page = write(
      'docs/a.md',
      '[ok](b.md#real-heading) [bad](b.md#nope)\n',
    );

    expect(checker.failuresIn(page), hasLength(1));
  });

  test('an anchor in the same page must name a heading', () {
    final page = write('a.md', '# Top\n\n[ok](#top) [bad](#nope)\n');

    expect(checker.failuresIn(page), hasLength(1));
  });

  test('a GitHub blob link resolves from the repository root', () {
    write('docs/recipes.md', '# Recipes\n');
    final page = write(
      'llms.txt',
      '[ok](${LinkChecker.blobPrefix}docs/recipes.md) '
          '[bad](${LinkChecker.blobPrefix}docs/gone.md)\n',
    );

    expect(checker.failuresIn(page), hasLength(1));
  });

  test('another absolute link is not checked', () {
    final page = write('a.md', '[x](https://pub.dev/packages/dio)\n');

    expect(checker.failuresIn(page), isEmpty);
  });
}
```

Create `packages/docs_check/test/links_test.dart`. It runs the checker over the real documents (the READMEs, the recipe pages, `docs/recipes.md`, `llms.txt`) and pins that the index and `llms.txt` list every recipe page and that `llms.txt` has absolute links only.

```dart
import 'package:test/test.dart';

import 'helpers/link_checker.dart';
import 'helpers/markdown_links.dart';
import 'helpers/repository_docs.dart';

void main() {
  final docs = RepositoryDocs();
  const links = MarkdownLinks();

  test('every link into the repository resolves', () {
    final checker = LinkChecker(docs.root);

    final failures = [
      for (final page in docs.checkedPages) ...checker.failuresIn(page),
    ];

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('llms.txt links only by absolute URL', () {
    final offenders = [
      for (final target in links.targetsIn(docs.llms.readAsStringSync()))
        if (!target.startsWith('https://')) target,
    ];

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('docs/recipes.md lists every recipe page', () {
    final index = docs.recipeIndex.readAsStringSync();

    final missing = [
      for (final page in docs.recipePages)
        if (!index.contains(docs.relativePath(page))) page.path,
    ];

    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('llms.txt lists every recipe page and the recipe index', () {
    final llms = docs.llms.readAsStringSync();

    final missing = [
      for (final page in docs.recipePages)
        if (!llms.contains(
          '${LinkChecker.blobPrefix}${docs.relativePath(page)}',
        ))
          page.path,
      if (!llms.contains('${LinkChecker.blobPrefix}docs/recipes.md'))
        'docs/recipes.md',
    ];

    expect(missing, isEmpty, reason: missing.join('\n'));
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd packages/docs_check && dart test test/link_checker_test.dart test/links_test.dart`
Expected: FAIL to compile: `helpers/link_checker.dart` does not exist.

- [ ] **Step 3: Write the link checker**

Create `packages/docs_check/test/helpers/link_checker.dart`:

```dart
import 'dart:io';

import 'markdown_links.dart';

/// Checks that the links of a page that point into this repository resolve.
///
/// A relative link is resolved from the page. An absolute link under
/// [blobPrefix] is resolved from the repository root. Every other absolute
/// link is not checked: the tests run without a network.
final class LinkChecker {
  /// Creates a checker for the repository at [root].
  const LinkChecker(this.root);

  /// The start of a GitHub link to a file of this repository on `main`.
  static const String blobPrefix =
      'https://github.com/4akloon/dart_token_manager/blob/main/';

  /// The repository root.
  final Directory root;

  static const MarkdownLinks _links = MarkdownLinks();

  /// The links of [page] that do not resolve, as readable messages.
  List<String> failuresIn(File page) {
    final text = page.readAsStringSync();
    final failures = <String>[];
    for (final target in _links.targetsIn(text)) {
      final problem = _problemWith(target, page, text);
      if (problem != null) {
        failures.add('${page.path}: ($target) $problem');
      }
    }
    return failures;
  }

  /// Why [target] does not resolve, or `null` when it does or is not checked.
  String? _problemWith(String target, File page, String text) {
    final hash = target.indexOf('#');
    final path = hash < 0 ? target : target.substring(0, hash);
    final anchor = hash < 0 ? null : target.substring(hash + 1);
    final file = _fileFor(path, page);
    if (file == null) {
      return null;
    }
    if (path.isEmpty) {
      return _missingAnchor(anchor, text);
    }
    if (FileSystemEntity.typeSync(file.path) == FileSystemEntityType.notFound) {
      return 'does not exist';
    }
    if (anchor != null && file.path.endsWith('.md') && file.existsSync()) {
      return _missingAnchor(anchor, file.readAsStringSync());
    }
    return null;
  }

  /// The local file [path] stands for, or `null` for a link not checked.
  File? _fileFor(String path, File page) {
    if (path.startsWith(blobPrefix)) {
      return File.fromUri(root.uri.resolve(path.substring(blobPrefix.length)));
    }
    if (path.contains(':')) {
      return null;
    }
    return File.fromUri(page.absolute.uri.resolve(path));
  }

  String? _missingAnchor(String? anchor, String text) {
    if (anchor == null || anchor.isEmpty) {
      return null;
    }
    return _links.anchorsIn(text).contains(anchor) ? null : 'has no heading';
  }
}
```

Run: `cd packages/docs_check && dart test test/link_checker_test.dart`
Expected: PASS.

Run: `cd packages/docs_check && dart test test/links_test.dart`
Expected: FAIL: `docs/recipes.md` and `llms.txt` do not exist, so `RepositoryDocs.recipeIndex` and `llms` read missing files.

- [ ] **Step 4: Write the recipe index**

Create `docs/recipes.md`. It uses relative links, because GitHub renders it in place:

```markdown
# Recipes

Copy-paste solutions for the common token tasks in Dart and Flutter. Every
recipe is one page with the complete code, what it does and the mistakes to
avoid. The code of each page lives in `example/recipes/` of its package, is
analyzed with the rest of the workspace, and is tested without a network.

## Find the recipe for your task

| I want to... | Recipe |
|---|---|
| sign the user in and keep the tokens fresh | [Sign in and store the tokens](../packages/token_manager/doc/recipes/login_and_set_tokens.md) |
| keep the user signed in after a restart | [Keep the session in secure storage](../packages/token_manager/doc/recipes/secure_token_store.md) |
| show the sign-in screen when the session ends | [Send the user to sign-in when the session ends](../packages/token_manager/doc/recipes/session_expiry.md) |
| test code that uses tokens without a network | [Test code that uses tokens without a network](../packages/token_manager/doc/recipes/testing_without_network.md) |
| replace a hand-written Dio refresh interceptor | [Replace a hand-written refresh interceptor](../packages/token_manager_dio/doc/recipes/replace_refresh_interceptor.md) |
| keep the login and the refresh request free of tokens in Dio | [Skip auth for the login and refresh endpoints](../packages/token_manager_dio/doc/recipes/skip_auth_endpoints.md) |
| add a bearer token and a refresh on 401 to `package:http` | [An authorized `http.Client`](../packages/token_manager_http/doc/recipes/authorized_client.md) |
| authorize unary and streaming gRPC calls | [Unary and streaming calls with one refresh](../packages/token_manager_grpc/doc/recipes/unary_and_streaming.md) |
| authorize GraphQL queries and subscriptions | [Queries and WebSocket subscriptions](../packages/token_manager_gql/doc/recipes/queries_and_subscriptions.md) |

## By package

| Package | Use it for | Recipes |
|---|---|---|
| [`token_manager`](../packages/token_manager/README.md) | storage, refresh and session state in any Dart code | sign in, secure storage, session expiry, testing |
| [`token_manager_dio`](../packages/token_manager_dio/README.md) | `dio` | replace an interceptor, skip auth endpoints |
| [`token_manager_http`](../packages/token_manager_http/README.md) | `package:http` | an authorized client |
| [`token_manager_grpc`](../packages/token_manager_grpc/README.md) | `package:grpc` | unary and streaming calls |
| [`token_manager_gql`](../packages/token_manager_gql/README.md) | GraphQL on `gql_link` | queries and subscriptions |

Start with the core recipe on signing in: every adapter recipe builds on a
`TokenManager`.
```

- [ ] **Step 5: Write llms.txt**

Create `llms.txt` at the repository root in the llms.txt convention: one title, one blockquote summary, then sections of links with a one-line description each. Every link is absolute (GitHub `blob/main`), because an agent may read the file outside the repository; the checker maps the prefix to local files.

```markdown
# dart_token_manager

> Client-side token lifecycle for Dart and Flutter: storage, single-flight refresh on 401, an observable session state and adapters for dio, package:http, gRPC and GraphQL. Use it instead of a hand-written refresh interceptor when several requests can fail with 401 at once. The core, `token_manager`, is pure Dart; each adapter attaches the header, recognises an auth failure and replays the request once, and never refreshes by itself.

Install the core plus the adapter for your transport from pub.dev. Every recipe below is complete, compiled code with a test.

## Packages

- [token_manager](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/README.md): the core. Token storage, single-flight refresh, typed refresh failures, session state stream.
- [token_manager_dio](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_dio/README.md): Dio interceptor that attaches the bearer token, refreshes once on 401 and retries.
- [token_manager_http](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_http/README.md): package:http Client that attaches the bearer token, refreshes once on 401 and replays.
- [token_manager_grpc](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_grpc/README.md): gRPC client interceptor for unary and streaming calls.
- [token_manager_gql](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_gql/README.md): gql_link Link for GraphQL queries, mutations and WebSocket subscriptions.

## Recipes

- [Recipe index](https://github.com/4akloon/dart_token_manager/blob/main/docs/recipes.md): every recipe by task and by package.
- [Sign in and store the tokens](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/recipes/login_and_set_tokens.md): create the manager, sign in, map refresh failures.
- [Keep the session in secure storage](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/recipes/secure_token_store.md): a custom TokenStore over secure storage.
- [Send the user to sign-in when the session ends](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/recipes/session_expiry.md): react to logout and a dead refresh token from the states stream.
- [Test code that uses tokens without a network](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/recipes/testing_without_network.md): fake clock, fake refresher, fake server.
- [Replace a hand-written Dio refresh interceptor](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_dio/doc/recipes/replace_refresh_interceptor.md): one refresh for parallel 401 responses.
- [Skip auth for the login and refresh endpoints in Dio](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_dio/doc/recipes/skip_auth_endpoints.md): a second Dio without the interceptor.
- [An authorized http.Client](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_http/doc/recipes/authorized_client.md): bearer token, refresh on 401 and replay for package:http.
- [Unary and streaming gRPC calls with one refresh](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_grpc/doc/recipes/unary_and_streaming.md): the interceptor for generated clients.
- [GraphQL queries and WebSocket subscriptions](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_gql/doc/recipes/queries_and_subscriptions.md): TokenManagerLink and TokenManagerSocketAuth.

## Migration

- [token_manager: migrating from 0.1](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/migration.md): mapping from the deprecated API.
- [token_manager_dio: migrating from 0.1](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_dio/doc/migration.md): RefreshInterceptor to DioTokenInterceptor.
- [token_manager_grpc: migrating from 0.1](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_grpc/doc/migration.md): RefreshInterceptor to GrpcTokenInterceptor.
```

- [ ] **Step 6: Link the new files from the root README**

In the "Documentation" list of the root `README.md`:

Replace

```markdown
- **[Core README](packages/token_manager/README.md)** — concepts, failures, `authorize`.
```

with

```markdown
- **[Recipes](docs/recipes.md)** — copy-paste solutions: sign in, secure storage, dio, http, gRPC, GraphQL.
- **[Core README](packages/token_manager/README.md)** — concepts, failures, `authorize`.
```

Replace

```markdown
- [Releasing](docs/releasing.md) — tags, OIDC publishing, release order.
```

with

```markdown
- [llms.txt](llms.txt) — the same entry points for a coding agent that reads the repository.
- [Releasing](docs/releasing.md) — tags, OIDC publishing, release order.
```

- [ ] **Step 7: Run the whole docs_check suite**

Run: `cd packages/docs_check && dart test`
Expected: PASS, every test of every file. If a link fails, the message names the page, the target and why (`does not exist` or `has no heading`).

- [ ] **Step 8: Format, analyze, commit**

Run: `dart format packages && dart analyze packages/docs_check`
Expected: `0 changed` and `No issues found!`.

```bash
git add docs/recipes.md llms.txt README.md packages/docs_check
git commit -m "docs: add the recipe index and llms.txt and check every link" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```


---

### Task 9: Release notes, dartdoc categories and verification

**Files:**
- Modify: `packages/<each>/CHANGELOG.md`, `packages/<each>/pubspec.yaml` (version, only if not yet bumped), `packages/<each>/dartdoc_options.yaml`

**Interfaces:**
- Consumes: the nine recipe pages (Tasks 3 to 7).
- Produces: the five packages at the target versions with a changelog line each.

- [ ] **Step 1: Find out which versions `main` has**

Run: `grep -m1 "^version" packages/*/pubspec.yaml && head -9 packages/*/CHANGELOG.md`
Expected: the version of every package and the top of its changelog.

Target versions: `token_manager` 0.2.1, `token_manager_dio` 0.2.1, `token_manager_grpc` 0.2.1, `token_manager_gql` 0.1.1, `token_manager_http` 0.1.1. Decide per package:

- **Case A: the package is already at the target** (the patch-release branch bumped it). Do not touch the version. Add one line, `Clearer description, topics and recipes.`, to the end of the existing top entry of its `CHANGELOG.md`, as its own paragraph.
- **Case B: the package is still at the previous version** (0.2.0 or 0.1.0). Bump `version:` in its `pubspec.yaml` to the target and add the entry below, directly under `# Changelog`.
- If a package is at neither, stop and ask: the release plan changed.

Case B entry (use the target version of the package, `0.1.1` for gql and http):

```markdown
# Changelog

## 0.2.1

Clearer description, topics and recipes.

## 0.2.0
```

There is no `**Breaking:**` marker and no bump of a package that did not change: all five changed here.

- [ ] **Step 2: Add the recipe pages to the dartdoc categories**

pub.dev shows the pages under `doc/` through `dartdoc_options.yaml` categories. In each package that has recipes make two edits: insert the category entries before `  categoryOrder:` and the keys into the order list before `  showUndocumentedCategories: true`. Keys and file names below; display names start with `Recipe:`.

**`packages/token_manager/dartdoc_options.yaml`**

Edit 1. Replace

```yaml
  categoryOrder:
```

with

```yaml
    recipe-login-and-set-tokens:
      markdown: doc/recipes/login_and_set_tokens.md
      displayName: "Recipe: Sign in and store the tokens"
    recipe-secure-token-store:
      markdown: doc/recipes/secure_token_store.md
      displayName: "Recipe: Keep the session in secure storage"
    recipe-session-expiry:
      markdown: doc/recipes/session_expiry.md
      displayName: "Recipe: Send the user to sign-in when the session ends"
    recipe-testing-without-network:
      markdown: doc/recipes/testing_without_network.md
      displayName: "Recipe: Test code that uses tokens without a network"
  categoryOrder:
```

Edit 2. Replace

```yaml
  showUndocumentedCategories
```

with

```yaml
    - recipe-login-and-set-tokens
    - recipe-secure-token-store
    - recipe-session-expiry
    - recipe-testing-without-network
  showUndocumentedCategories
```

**`packages/token_manager_dio/dartdoc_options.yaml`**

Edit 1. Replace

```yaml
  categoryOrder:
```

with

```yaml
    recipe-replace-refresh-interceptor:
      markdown: doc/recipes/replace_refresh_interceptor.md
      displayName: "Recipe: Replace a hand-written refresh interceptor"
    recipe-skip-auth-endpoints:
      markdown: doc/recipes/skip_auth_endpoints.md
      displayName: "Recipe: Skip auth for the login and refresh endpoints"
  categoryOrder:
```

Edit 2. Replace

```yaml
  showUndocumentedCategories
```

with

```yaml
    - recipe-replace-refresh-interceptor
    - recipe-skip-auth-endpoints
  showUndocumentedCategories
```

**`packages/token_manager_http/dartdoc_options.yaml`**

Edit 1. Replace

```yaml
  categoryOrder:
```

with

```yaml
    recipe-authorized-client:
      markdown: doc/recipes/authorized_client.md
      displayName: "Recipe: An authorized http.Client"
  categoryOrder:
```

Edit 2. Replace

```yaml
  showUndocumentedCategories
```

with

```yaml
    - recipe-authorized-client
  showUndocumentedCategories
```

**`packages/token_manager_grpc/dartdoc_options.yaml`**

Edit 1. Replace

```yaml
  categoryOrder:
```

with

```yaml
    recipe-unary-and-streaming:
      markdown: doc/recipes/unary_and_streaming.md
      displayName: "Recipe: Unary and streaming calls with one refresh"
  categoryOrder:
```

Edit 2. Replace

```yaml
  showUndocumentedCategories
```

with

```yaml
    - recipe-unary-and-streaming
  showUndocumentedCategories
```

**`packages/token_manager_gql/dartdoc_options.yaml`**

Edit 1. Replace

```yaml
  categoryOrder:
```

with

```yaml
    recipe-queries-and-subscriptions:
      markdown: doc/recipes/queries_and_subscriptions.md
      displayName: "Recipe: Queries and WebSocket subscriptions"
  categoryOrder:
```

Edit 2. Replace

```yaml
  showUndocumentedCategories
```

with

```yaml
    - recipe-queries-and-subscriptions
  showUndocumentedCategories
```

- [ ] **Step 3: Verify the docs and the package archives**

```bash
for p in token_manager token_manager_dio token_manager_http token_manager_grpc token_manager_gql; do
  (cd packages/$p && dart doc --dry-run 2>&1 | tail -3)
done
```

Expected: for each package the last lines say `Found 0 warnings and 0 errors` (dartdoc), and no `Recipe:` category is reported as missing.

- [ ] **Step 4: Verify with the full gates and commit**

Run: `dart format packages && dart format packages`
Expected: the second run changes 0 files.

Run: `dart analyze packages`
Expected: `No issues found!`

Commit first (the dry run warns about a dirty tree), then verify:

```bash
git add packages/*/CHANGELOG.md packages/*/pubspec.yaml packages/*/dartdoc_options.yaml
git commit -m "docs: add the recipe categories and the changelog entries of the patch release" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

```bash
for p in token_manager token_manager_dio token_manager_http token_manager_grpc token_manager_gql; do
  (cd packages/$p && dart pub publish --dry-run 2>&1 | tail -3)
done
```

Expected: each package ends with `Package has 0 warnings.` Any warning about the description or topics is a failure of Task 1.

```bash
for p in token_manager token_manager_dio token_manager_http token_manager_grpc token_manager_gql docs_check; do
  (cd packages/$p && dart test)
done
```

Expected: all pass, including `test/quality/size_limits_test.dart` of each package. If a recipe file triggers the size limits, split the recipe; do not add an allowlist entry.

- [ ] **Step 5: Hand over**

Do not push or tag: releasing follows `docs/releasing.md`. In the pull request description record, after the packages are published, the pub.dev search results for the queries of the spec ("Search queries"); the result is reported there, never promised in the docs.
