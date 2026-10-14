# Contributing to dart_token_manager

Thanks for helping build dart_token_manager! This guide covers *developing the project itself* —
setup, day-to-day commands, the architecture, and the conventions to follow. The package READMEs stay
user-facing; this file and [CLAUDE.md](CLAUDE.md) (the exhaustive repo guide: code rules, size limits,
design rules) are for contributors, human or agent.

## Contents

- [Prerequisites](#prerequisites)
- [Getting the code](#getting-the-code)
- [Repository layout](#repository-layout)
- [Everyday commands](#everyday-commands)
- [Architecture at a glance](#architecture-at-a-glance)
- [Tests](#tests)
- [Commits and changelog](#commits-and-changelog)
- [Releasing](#releasing)

## Prerequisites

- **Dart SDK `>=3.10.0 <4.0.0`** — the whole workspace targets this range.

## Getting the code

This repo is a **Dart pub workspace** (monorepo): one `dart pub get` at the root resolves every member
together against a single lockfile.

```sh
git clone https://github.com/4akloon/dart_token_manager && cd dart_token_manager
dart pub get
```

## Repository layout

See the [packages table in the root README](README.md#packages) for what each package does. Key points
for contributors:

- Core lives in `packages/token_manager`: pure Dart, **no runtime dependencies**, no knowledge of HTTP.
  `lib/token_manager.dart` is the only public barrel; the rest is under `lib/src/`.
- Adapters (`token_manager_dio`, `token_manager_grpc`, `token_manager_gql`) depend only on the core and
  their transport.
- `test/` mirrors `lib/src/`; shared fakes are in `test/helpers/`.

## Everyday commands

| Command | Effect |
|---|---|
| `dart pub get` | Resolve the whole workspace. |
| `dart format packages` | Format; a second run must change 0 files. |
| `dart analyze packages` | Must print `No issues found!`. |
| `cd packages/<package> && dart test` | Run one package's tests. |
| `dart pub publish --dry-run` | Validate a publishable package (run inside it). |

Formatting and analysis must be clean before a pull request is opened. CI runs the same checks.

## Architecture at a glance

- **The core knows nothing about HTTP.** An adapter attaches the header, recognises an auth failure and
  replays once. It never refreshes by itself.
- **Single-flight refresh.** One shared in-flight future, plus a compare of the rejected token with the
  current one. The state and concurrency live in `lib/src/engine/token_engine.dart`.
- **Typed failures.** A terminal `InvalidGrant` logs out; a `Transient` failure never does.
- **Streams are never consumed with `await for`** in library code, so pause, resume and cancel reach the
  source.

The code rules, size limits and design rules are in [CLAUDE.md](CLAUDE.md).

## Tests

Write the failing test first. Tests mirror `lib/src/` under `test/`, use the fakes in `test/helpers/`,
and never touch the network. File-size limits are enforced by `test/quality/size_limits_test.dart`, a
ratchet: an allowlist entry may only shrink.

## Commits and changelog

Use Conventional Commits with a package scope, for example `feat(token_manager): add validToken`.
Update the `CHANGELOG.md` of every package whose public behaviour changes; before 1.0 a breaking change
is a minor bump, and only the changed package is bumped.

## Releasing

See [docs/releasing.md](docs/releasing.md).
