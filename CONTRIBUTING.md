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
