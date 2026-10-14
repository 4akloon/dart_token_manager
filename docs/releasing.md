# Releasing

Packages are published to pub.dev from GitHub Actions with OIDC automated
publishing. There are no secrets. The workflow is
`.github/workflows/publish.yml`; it runs when a tag `<package>-vX.Y.Z` is
pushed. CI also runs `dart pub publish --dry-run` for every package.

> **Status:** `token_manager`, `token_manager_dio` and `token_manager_grpc` 0.1.x
> are on pub.dev; 0.2.0 of these three and `token_manager_gql` 0.1.0 are the
> pending release. `token_manager_gql` does not exist on pub.dev yet.

## One-time setup

For each package (`token_manager`, `token_manager_dio`, `token_manager_grpc`,
`token_manager_gql`):

1. The package must already exist on pub.dev. Only a brand-new package
   (`token_manager_gql` now, `token_manager_http` later) needs a manual first
   publish: run `dart pub publish` from `packages/<package>`. The other
   packages are already on pub.dev.
2. On pub.dev open the package, then Admin, then Automated publishing, and
   enable GitHub Actions publishing:
   - Repository: `4akloon/dart_token_manager`
   - Tag pattern: `<package>-v{{version}}`
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

Release **`token_manager`** (the core) first. The adapters depend on it with a
`^0.2.0` style constraint that resolves from pub.dev, so a new adapter release
that needs a new core version can only be published after the core is live.
