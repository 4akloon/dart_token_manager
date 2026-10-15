# Getting started

A `TokenManager<T>` owns the tokens of one session. You give it three things:
where tokens are kept, how to refresh them, and when they expire. It gives
back tokens that are valid now.

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

TokenManager<TokenSet> buildManager() {
  return TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: MyRefresher(),
    info: const TokenSetInfo(),
  );
}
```

## Sign in

`setTokens` stores the tokens and makes them the current session.

```dart
Future<void> signIn(TokenManager<TokenSet> manager, TokenSet tokens) async {
  await manager.setTokens(tokens);
}
```

`setTokens(null)` is the same as `logout()`.

## Read tokens

```dart
Future<void> read(TokenManager<TokenSet> manager) async {
  final stored = await manager.current(); // never refreshes; may be null
  final valid = await manager.validToken(); // refreshes when needed
  print('${stored?.accessToken} ${valid.accessToken}');
}
```

`validToken` refreshes when `info` says the tokens expire within `skew`
(30 seconds by default). It throws `NotAuthenticated` when nobody is signed in.

To spare the caller that pays for a refresh, pass `refreshAhead` (for example
`Duration(minutes: 5)`) to `create`: tokens that are close to expiry are then
returned at once and refreshed in the background. To refresh at a moment you
choose, such as start-up, call `refreshIfNeeded()`. Neither uses a timer; see
[Refreshing](refreshing.md).

## Authorize a call

```dart
Future<String> fetchUser(TokenManager<TokenSet> manager) {
  return manager.authorize(
    (tokens) async => 'user for ${tokens.accessToken}', // your request here
    isAuthFailure: (error) => error is StateError, // e.g. an HTTP 401
  );
}
```

When `send` fails with an auth failure, the manager reports the tokens as
rejected, refreshes them and calls `send` once more. A second failure
propagates.

## Sign out and clean up

```dart
Future<void> signOut(TokenManager<TokenSet> manager) async {
  await manager.logout(); // deletes the stored tokens
  await manager.dispose(); // closes `states`; call when the manager is done
}
```

## Where to go next

- [Concepts](concepts.md) — when a refresh happens and why it is single-flight.
- [Storage](storage.md) — persist tokens in secure storage.
- [Refreshing](refreshing.md) — implement the `TokenRefresher` properly.
- [Streams](streams.md) — authorize long-lived streams.
