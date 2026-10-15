# token_manager

[![Pub Version](https://img.shields.io/pub/v/token_manager.svg)](https://pub.dev/packages/token_manager)
![Dart](https://img.shields.io/badge/Dart-%3E%3D3.10-0175C2?logo=dart&logoColor=white)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![Part of](https://img.shields.io/badge/part_of-dart__token__manager-informational)

**Dart refresh token and OAuth/JWT session management without races** — `token_manager` stores the access
and refresh tokens, refreshes them once for any number of concurrent callers (single-flight) and exposes
the session as a stream. It is the core of [dart_token_manager](https://github.com/4akloon/dart_token_manager).
Pure Dart, no runtime dependencies, and it knows nothing about HTTP: the transport adapters
([`token_manager_dio`](https://pub.dev/packages/token_manager_dio),
[`token_manager_http`](https://pub.dev/packages/token_manager_http),
[`token_manager_grpc`](https://pub.dev/packages/token_manager_grpc),
[`token_manager_gql`](https://pub.dev/packages/token_manager_gql)) plug into it.

> Refresh is on demand: tokens are refreshed when `validToken`, `authorize` or a rejected token asks for it.
> There is no background timer; `refreshAhead` and `refreshIfNeeded` move the refresh off the request path
> (see [Refreshing before expiry](#refreshing-before-expiry)).

**Recipes:** [Sign in and store the tokens](doc/recipes/login_and_set_tokens.md) · [Keep the session in secure storage](doc/recipes/secure_token_store.md) · [Send the user to sign-in when the session ends](doc/recipes/session_expiry.md) · [Refresh the session on app resume](doc/recipes/refresh_on_resume.md) · [Test code that uses tokens without a network](doc/recipes/testing_without_network.md)

## Contents

- [Install](#install)
- [Should I use this?](#should-i-use-this)
- [Quick start](#quick-start)
- [Session state](#session-state)
- [Authorizing calls](#authorizing-calls)
- [Refreshing before expiry](#refreshing-before-expiry)
- [Errors](#errors)
- [Migrating from 0.1](#migrating-from-01)
- [Recipes](#recipes)
- [Reference](#reference)

## Install

```yaml
dependencies:
  token_manager: ^0.2.0
```

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

```dart
import 'package:token_manager/token_manager.dart';

final class MyRefresher implements TokenRefresher<TokenSet> {
  @override
  Future<TokenSet> refresh(TokenSet current) async {
    // Call your token endpoint with current.refreshToken.
    return TokenSet(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(), // or a persistent TokenStore
    refresher: MyRefresher(),
    info: const TokenSetInfo(),
  );

  await manager.setTokens(
    TokenSet(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );

  final tokens = await manager.validToken(); // refreshes when about to expire
  print(tokens.accessToken);
}
```

`TokenSet` is a ready-made token value; to use your own type `T`, implement `TokenStore<T>`,
`TokenRefresher<T>` and `TokenInfo<T>`. A runnable version is in [example/main.dart](example/main.dart).

**[doc/getting_started.md](doc/getting_started.md)** walks through the setup step by step.

## Session state

`manager.states` replays the latest `AuthState` to every listener, then emits each change.

```dart
manager.states.listen((state) {
  switch (state) {
    case Unauthenticated():
      print('signed out');
    case Authenticated(:final tokens):
      print('signed in: ${tokens.accessToken}');
    case Refreshing():
      print('refreshing');
  }
});
```

| State | Meaning |
|---|---|
| `Unauthenticated` | There are no tokens; the user is signed out. |
| `Authenticated` | Signed in with the carried tokens. |
| `Refreshing` | A refresh is running; the carried tokens are the ones being replaced. |

**[doc/concepts.md](doc/concepts.md)** explains how the state and the refresh fit together.

## Authorizing calls

`authorize` runs a call with valid tokens and replays it once when the server rejects them.
`authorizeStream` does the same for streams, and never uses `await for`, so pause, resume and cancel
reach the source.

```dart
final user = await manager.authorize(
  (tokens) => api.fetchUser(tokens.accessToken),
  isAuthFailure: (error) => error is ApiException && error.statusCode == 401,
);

final events = manager.authorizeStream(
  (tokens) => api.watchEvents(tokens.accessToken),
  isAuthFailure: (error) => error is ApiException && error.statusCode == 401,
);
```

`validToken({rejected})` is the primitive underneath: concurrent callers share one refresh, and the tokens
a server just rejected are refreshed unless another caller already replaced them.

**[doc/streams.md](doc/streams.md)** · **[doc/refreshing.md](doc/refreshing.md)**

## Refreshing before expiry

`validToken` waits for a refresh only when less than `skew` is left. Set `refreshAhead` to refresh earlier,
in the background:

```dart
final manager = TokenManager<TokenSet>.create(
  store: InMemoryTokenStore<TokenSet>(),
  refresher: MyRefresher(),
  info: const TokenSetInfo(),
  refreshAhead: const Duration(minutes: 5), // must be greater than skew
);
```

A call that finds the tokens with less than five minutes but more than `skew` left gets them at once and starts
the refresh behind it. A failed background refresh never signs the user out unless the server rejected the refresh token.

`refreshIfNeeded` refreshes at a moment you choose and waits for it, for example at start-up or when the app
returns to the foreground:

```dart
await manager.refreshIfNeeded(within: const Duration(minutes: 10));
```

**[doc/refreshing.md](doc/refreshing.md)** has the windows and the failure rules; [Refresh the session on app resume](doc/recipes/refresh_on_resume.md) is a complete recipe.

## Errors

| Thrown | When |
|---|---|
| `NotAuthenticated` | `validToken` or `authorize` ran without a session. |
| `InvalidGrant` | The refresh token was rejected for good; the session ends and `states` emits `Unauthenticated`. |
| `Transient` | The refresh failed for a reason that may go away; the session stays and the next call retries. |

A `TokenRefresher` throws `InvalidGrant` or `Transient`; any other exception it throws is treated as
transient. Storage failures are never reported as refresh failures.

**[doc/storage.md](doc/storage.md)** covers the failure semantics of the store.

## Migrating from 0.1

The old API still works in 0.2, marked `@Deprecated`. See **[doc/migration.md](doc/migration.md)**.

## Recipes

Each recipe is one page with complete code that is compiled and tested in this repository.

- [Sign in and store the tokens](doc/recipes/login_and_set_tokens.md)
- [Keep the session in secure storage](doc/recipes/secure_token_store.md)
- [Send the user to sign-in when the session ends](doc/recipes/session_expiry.md)
- [Refresh the session on app resume](doc/recipes/refresh_on_resume.md)
- [Test code that uses tokens without a network](doc/recipes/testing_without_network.md)

## Reference

| Guide | Topic |
|---|---|
| [Getting started](doc/getting_started.md) | Create a manager, sign in, read tokens, authorize a call |
| [Concepts](doc/concepts.md) | Layers, single-flight refresh, rejected-token compare, sessions |
| [Storage](doc/storage.md) | `TokenStore`, `InMemoryTokenStore`, writing a secure-storage store |
| [Refreshing](doc/refreshing.md) | `TokenRefresher`, `TokenInfo` and skew, refreshing before expiry, failure types |
| [Streams](doc/streams.md) | `authorizeStream` and its pause/resume/cancel contract |
| [Testing](doc/testing.md) | `Clock`, fakes, how this package's tests are built |
| [Migrating from 0.1](doc/migration.md) | Mapping from the deprecated API |

Generate API docs: `cd packages/token_manager && dart doc .`
