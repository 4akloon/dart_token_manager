# Agent discoverability: design

## Goal

When a coding agent in someone else's Dart or Flutter project is asked to
"add token refresh", "attach a bearer token to dio", or "handle 401 with a
refresh", it should find the `token_manager` packages, pick them over a
hand-written interceptor, and have a recipe it can copy.

Success criteria:

- The five packages show up on pub.dev for the queries in
  [Search queries](#search-queries).
- A package page answers "should I use this?" in its first screen.
- Every common scenario has one recipe whose code is compiled and analyzed,
  so it cannot rot.
- A GitHub-reading agent finds the recipes from one file (`llms.txt`).

## Scope

Audience (decided with the user): an agent in a project that does not use the
packages yet, finding them through pub.dev search, web search and training
data. Agents already using the packages (AGENTS.md, skills), MCP servers and
registries, and external posts are out of scope; see [Follow-ups](#follow-ups).

Release: patch versions only. This work changes metadata, documentation and
examples, never `lib/`. It ships together with the patch release prepared on
`chore/patch-releases`: `token_manager` 0.2.1, `token_manager_dio` 0.2.1,
`token_manager_grpc` 0.2.1, `token_manager_gql` 0.1.1,
`token_manager_http` 0.1.1. The work starts after that branch is merged, so
the CHANGELOG entries and version bumps are made once, not twice.

## Search queries

The queries the metadata and README openings are written for:

- dart refresh token, dart oauth token refresh, dart jwt refresh
- dio refresh token interceptor, dio 401 retry
- http client bearer token refresh, package:http authorization
- grpc dart auth token interceptor
- graphql dart auth token, gql_link authorization
- flutter secure token storage session expired

## Design

### 1. Metadata (all five packages)

`pubspec.yaml` `description` (60 to 180 characters, one sentence, names the
transport and the problem) and `topics` (at most five, lowercase). Proposed
values, to be re-checked against pub.dev's rules when implementing:

| Package | Topics |
|---|---|
| `token_manager` | `authentication`, `oauth`, `jwt`, `refresh-token`, `token` |
| `token_manager_dio` | `dio`, `authentication`, `interceptor`, `oauth`, `refresh-token` |
| `token_manager_http` | `http`, `authentication`, `oauth`, `refresh-token`, `jwt` |
| `token_manager_grpc` | `grpc`, `authentication`, `interceptor`, `oauth`, `refresh-token` |
| `token_manager_gql` | `graphql`, `gql`, `authentication`, `oauth`, `refresh-token` |

Descriptions open with the verb and the transport, for example "Single-flight
OAuth/JWT refresh for Dio: attaches the access token, refreshes once on 401
and replays the request." The descriptions of `token_manager_gql` and
`token_manager_http` are kept if they already read this way.

### 2. README: "Should I use this?"

Each package README gets, right after the install section, a short block:

- **Use it when:** the app has an access and a refresh token, several requests
  can run at once, and a 401 must trigger exactly one refresh.
- **You do not need it when:** the API uses a long-lived static key, or the
  app never refreshes tokens.
- **What it replaces:** the hand-written interceptor that refreshes in
  `onError` (race: N parallel 401s cause N refreshes; a failed refresh loops).
- **Which package:** a four-line table linking the core and the adapters.

Rules: no claims about named third-party packages (they cannot be verified
and go stale); compare approaches, not products. The first sentence of each
README repeats the problem in the words of the search queries.

### 3. Recipes

One recipe is one page that answers one task, with the complete code, the
expected behaviour, and a "common mistakes" list. Recipes live in the package
that owns the code (so pub.dev publishes them) under `doc/recipes/`, and
`docs/recipes.md` at the repository root indexes all of them.

| Package | Recipes |
|---|---|
| `token_manager` | login and `setTokens`; secure persistence with a custom store; logout and session expiry from `states`; testing auth code without a network |
| `token_manager_dio` | replace a hand-written refresh interceptor; skip auth for the login and refresh endpoints |
| `token_manager_http` | an authorized `http.Client` |
| `token_manager_grpc` | unary and streaming calls with one refresh |
| `token_manager_gql` | queries and WebSocket subscriptions |

Each recipe's code lives in `example/recipes/<name>.dart` of its package,
with the page including it verbatim. `dart analyze packages` therefore checks
every recipe, and each example that can run without a network has a test. The
repository rules apply to examples: no top-level functions except `main`.

### 4. Files for agents that read the repository

- `llms.txt` at the repository root, in the llms.txt convention: one title,
  one summary paragraph, then links to the README of each package, the recipe
  index and the migration pages, each with a one-line description.
- No `AGENTS.md`, skill or MCP entry (out of scope).

### 5. Release notes

Each changed package gets a CHANGELOG entry in the existing format (bare
`## x.y.z` heading, one-line summary): "Clearer description, topics and
recipes", no `**Breaking:**`.

## Testing

- `dart format packages` second run 0 changed; `dart analyze packages` clean
  (this covers the recipe code).
- Tests for the recipes that run offline.
- `dart doc --dry-run` 0 warnings; `dart pub publish --dry-run` in each
  package shows no warnings about description or topics.
- A link check over `docs/recipes.md`, `llms.txt` and the README blocks:
  every relative link resolves.
- After release: the pub.dev search for the queries above is checked and the
  result is recorded in the PR description, not promised in the docs.

## Risks

- The search ranking depends on pub.dev's own signals (likes, points,
  popularity); metadata helps but does not guarantee placement.
- Descriptions and topics only reach pub.dev with a release, so nothing
  improves until the patches are published.
- Recipes duplicate parts of the guides; the recipes link to the guides
  instead of repeating the reference text.

## Follow-ups

Not part of this work: an `AGENTS.md` or skill for projects that adopt the
packages, an entry in Dart MCP or plugin registries, articles and Stack
Overflow answers, an Awesome Dart entry. Each is a separate piece of work.
