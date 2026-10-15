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
- `packages/token_manager_dio`, `packages/token_manager_grpc`,
  `packages/token_manager_gql`, `packages/token_manager_http`: transport
  adapters. They depend only on the core and their transport: dio, gRPC,
  `gql_link` (a `Link` plus WebSocket auth callbacks) and `package:http`
  (a `Client` wrapper).
- `test/` mirrors `lib/src/`; shared fakes are in `test/helpers/`; the size
  limits are enforced by `test/quality/size_limits_test.dart`.
- `packages/docs_check`: not published. Its tests check the pubspec metadata,
  the README blocks, the recipe pages (their `<!-- include: path -->` code
  blocks equal the files in `example/recipes/`), `docs/recipes.md`, `llms.txt`
  and every link between them. Run `cd packages/docs_check && dart test`.

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

`TokenManager.create` is the one allowed exception to the five-parameter limit (it has six named parameters because `skew` and `refreshAhead` are separate options); no other API gets this exception.

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
