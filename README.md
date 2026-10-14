# dart_token_manager

[![CI](https://github.com/4akloon/dart_token_manager/actions/workflows/ci.yml/badge.svg)](https://github.com/4akloon/dart_token_manager/actions/workflows/ci.yml)
![Dart](https://img.shields.io/badge/Dart-%3E%3D3.10-0175C2?logo=dart&logoColor=white)
![Transports](https://img.shields.io/badge/transports-dio%20%7C%20gRPC%20%7C%20GraphQL-informational)
![Status](https://img.shields.io/badge/status-pre--release-orange)
![License](https://img.shields.io/badge/license-MIT-brightgreen)

**Client-side token lifecycle for Dart — storage, single-flight refresh, an observable session
state, and thin transport adapters for dio, gRPC and GraphQL.**

- 🔁 **Single-flight refresh** — concurrent callers share one in-flight refresh; a token the server rejected is refreshed only if nobody replaced it already.
- 🧱 **Layered core** — `TokenManager<T>` composes a `TokenStore`, a `TokenRefresher` and a `TokenInfo`; pure Dart, no runtime dependencies, no knowledge of HTTP.
- 🚦 **Typed failures** — a sealed `RefreshFailure`: `InvalidGrant` ends the session, `Transient` never does; no tokens means `NotAuthenticated`.
- 📡 **Observable session** — `states` replays the latest `AuthState` (`Unauthenticated`, `Authenticated`, `Refreshing`) to every listener.
- 🔌 **Thin adapters** — attach the header, recognise an auth failure, replay once. An adapter never refreshes by itself.
- 🌊 **Stream-safe** — `authorizeStream` reopens a stream once without `await for`, so pause, resume and cancel reach the source.

```dart
import 'package:token_manager/token_manager.dart';

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(), // or a persistent TokenStore
    refresher: MyRefresher(), // your TokenRefresher<TokenSet>
    info: const TokenSetInfo(),
  );

  await manager.setTokens(
    TokenSet(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );

  // Valid tokens, refreshed first if about to expire; replayed once on rejection.
  final profile = await manager.authorize(
    (tokens) => fetchProfile(tokens.accessToken),
    isAuthFailure: (error) => error is UnauthorizedException,
  );
  print(profile);

  await manager.dispose();
}
```

> **Status: pre-release.** The packages are not on pub.dev yet: the first release is pending, so
> the version constraints below resolve only after it. Until then use a path or git dependency.

---

## Table of contents

- [Why dart_token_manager](#why-dart_token_manager)
- [Packages](#packages)
- [Install](#install)
- [Getting started](#getting-started)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Why dart_token_manager

Every app that talks to an authenticated API re-implements the same fragile loop: attach a token,
catch a 401, refresh, retry — and race itself when ten requests fail at once.

- **One refresh, many callers.** The engine keeps a single shared in-flight future and compares the
  rejected token with the current one, so a burst of 401s triggers exactly one refresh.
- **The core knows nothing about HTTP.** Transport adapters recognise an auth failure in their own
  terms and ask the manager for a replacement; they never refresh on their own.
- **Failures are typed.** A terminal `InvalidGrant` logs out; a `Transient` failure keeps the
  session, so a flaky network never signs the user out.

## Packages

This repo is a Dart **pub workspace** (monorepo). Dart SDK: `>=3.10.0 <4.0.0`.

| Package | Role |
|---|---|
| [`token_manager`](packages/token_manager) | **Core** (`^0.2.0`): `TokenManager<T>`, `TokenStore` / `TokenRefresher` / `TokenInfo`, `AuthState`, **single-flight refresh**, `authorize` / `authorizeStream`, sealed `RefreshFailure` (`InvalidGrant` / `Transient`), `NotAuthenticated`. |
| [`token_manager_dio`](packages/token_manager_dio) | **dio** adapter (`^0.2.0`) — `DioTokenInterceptor`. |
| [`token_manager_grpc`](packages/token_manager_grpc) | **gRPC** adapter (`^0.2.0`) — `GrpcTokenInterceptor`. |
| [`token_manager_gql`](packages/token_manager_gql) | **GraphQL** adapter (`^0.1.0`) — `TokenManagerLink` for [`gql_link`](https://pub.dev/packages/gql_link) (`graphql`, `graphql_flutter`, `ferry`). |
| `token_manager_http` | **Planned** — `HttpTokenClient` for [`package:http`](https://pub.dev/packages/http). |

## Install

Add the core and the adapter for your transport:

```yaml
dependencies:
  token_manager: ^0.2.0
  token_manager_dio: ^0.2.0    # or token_manager_grpc: ^0.2.0 / token_manager_gql: ^0.1.0
```

> The first release is pending, so these constraints do not resolve on pub.dev yet.

## Getting started

### 1. Implement a refresher

A `TokenRefresher<T>` exchanges the current tokens for new ones. Throw `InvalidGrant` when the
refresh token is rejected for good, `Transient` when the failure may go away.

```dart
import 'package:token_manager/token_manager.dart';

final class MyRefresher implements TokenRefresher<TokenSet> {
  const MyRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    // Call your auth endpoint with current.refreshToken here.
    return TokenSet(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}
```

### 2. Create the manager

```dart
final manager = TokenManager<TokenSet>.create(
  store: InMemoryTokenStore<TokenSet>(), // or a persistent TokenStore
  refresher: const MyRefresher(),
  info: const TokenSetInfo(),
);

await manager.setTokens(
  TokenSet(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  ),
);

manager.states.listen((state) => print(state)); // Authenticated, Refreshing, ...
```

`TokenSet` is a ready-made token value; for your own type `T`, implement `TokenStore<T>`,
`TokenRefresher<T>` and `TokenInfo<T>`.

### 3. Attach it to your transport

```dart
import 'package:dio/dio.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const BearerDelegate();

  @override
  void applyTo(RequestOptions options, TokenSet tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
  }
}

final dio = Dio();
dio.interceptors.add(
  DioTokenInterceptor<TokenSet>(
    manager: manager,
    delegate: const BearerDelegate(),
    dio: dio, // the replay keeps this client's adapter, interceptors and timeouts
  ),
);
```

gRPC and GraphQL follow the same shape — see
[`token_manager_grpc`](packages/token_manager_grpc/README.md) and
[`token_manager_gql`](packages/token_manager_gql/README.md).

## Documentation

- **[Core README](packages/token_manager/README.md)** — concepts, failures, `authorize`.
- **[Migrating from 0.1](packages/token_manager/doc/migration.md)** — the redesign of the core.
- [dio](packages/token_manager_dio/README.md) · [gRPC](packages/token_manager_grpc/README.md) · [GraphQL](packages/token_manager_gql/README.md) — adapter guides.
- [Releasing](docs/releasing.md) — tags, OIDC publishing, release order.
- [Design spec](docs/superpowers/specs/2026-10-14-token-manager-redesign-design.md) — the redesign.

## Contributing

```sh
dart pub get
dart format packages && dart analyze packages
cd packages/token_manager && dart test
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and [CLAUDE.md](CLAUDE.md) for the code rules.

## License

MIT — see [LICENSE](packages/token_manager/LICENSE).
