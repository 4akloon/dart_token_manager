# token_manager

[![Pub Version](https://img.shields.io/pub/v/token_manager.svg)](https://pub.dev/packages/token_manager)

Token lifecycle management for Dart: storage, single-flight refresh and an
observable session state. The core has no dependencies and knows nothing about
HTTP; transport packages (`token_manager_dio`, `token_manager_grpc`) plug into
it.

## Installation

```yaml
dependencies:
  token_manager: ^0.2.0
```

## Quick start

```dart
import 'package:token_manager/token_manager.dart';

final manager = TokenManager<TokenSet>.create(
  store: InMemoryTokenStore<TokenSet>(), // or a persistent TokenStore
  refresher: MyRefresher(), // implements TokenRefresher<TokenSet>
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
```

`TokenSet` is a ready-made token value; use your own type `T` by implementing
`TokenStore<T>`, `TokenRefresher<T>` and `TokenInfo<T>`.

## Concepts

- **`validToken({rejected})`** returns tokens that are valid now. Concurrent
  callers share one refresh. Pass the tokens a server just rejected as
  `rejected`: they are refreshed unless another caller already replaced them.
  It throws `NotAuthenticated` when there is no session.
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
- Refresh happens on demand, when `validToken`, `authorize` or a rejected token
  asks for it; there is no background timer.

## Migrating from 0.1

See [doc/migration.md](doc/migration.md).
