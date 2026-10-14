# Refreshing

A `TokenRefresher<T>` exchanges the current tokens for new ones. The manager
decides when to call it; you decide how, and how it fails.

```dart
import 'package:token_manager/token_manager.dart';

final class HttpRefresher implements TokenRefresher<TokenSet> {
  @override
  Future<TokenSet> refresh(TokenSet current) async {
    final response = await _post(current.refreshToken);
    if (response.status == 400) {
      throw const InvalidGrant(); // the refresh token is dead
    }
    if (response.status != 200) {
      throw Transient('token endpoint answered ${response.status}');
    }
    return TokenSet(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }

  // Your HTTP call goes here.
  Future<({int status, String accessToken, String refreshToken})> _post(
    String? refreshToken,
  ) async => (status: 200, accessToken: 'a', refreshToken: 'r');
}
```

## When a refresh runs

`validToken` refreshes when any of these holds:

- the tokens were passed as `rejected` and are still the current ones;
- `info.expiresAt(tokens)` is within `skew` of now.

Without a `refresher` tokens are never refreshed; without `info` they never
expire (a rejected token can still trigger a refresh).

## TokenInfo and skew

`TokenInfo<T>` answers one question: when do these tokens expire, or `null`
for never. `TokenSetInfo` reads `TokenSet.expiresAt`.

```dart
import 'package:token_manager/token_manager.dart';

final class JwtInfo implements TokenInfo<String> {
  const JwtInfo();

  @override
  DateTime? expiresAt(String jwt) => null; // decode the `exp` claim here
}

final class StringRefresher implements TokenRefresher<String> {
  @override
  Future<String> refresh(String current) async => current;
}

final manager = TokenManager<String>.create(
  store: InMemoryTokenStore<String>(),
  refresher: StringRefresher(),
  info: const JwtInfo(),
  skew: const Duration(minutes: 1), // refresh one minute early
);
```

`skew` defaults to 30 seconds. It absorbs clock drift and request latency: a
token that would expire mid-flight is refreshed first.

## InvalidGrant vs Transient

| Throw | Meaning | Effect |
|---|---|---|
| `InvalidGrant` | The refresh token was rejected for good. | The store is cleared, `states` emits `Unauthenticated`, every waiter gets `InvalidGrant`. |
| `Transient` | The failure may go away (no network, a 5xx). | The session stays; the state returns to `Authenticated`; the next `validToken` retries. |
| any other `Exception` | Unknown. | Wrapped in `Transient`. |

Throw `InvalidGrant` only when the server said the grant is dead. Logging the
user out on a flaky network is the worst failure mode. An `Error` is never
caught and propagates.

## NotAuthenticated

`validToken` and `authorize` throw `NotAuthenticated` when there is no
session. It is also what a waiter receives when its refresh was superseded by
a logout.

```dart
import 'package:token_manager/token_manager.dart';

Future<void> guarded(TokenManager<TokenSet> manager) async {
  try {
    await manager.validToken();
  } on NotAuthenticated {
    print('show the sign-in screen');
  } on InvalidGrant {
    print('the session ended; show the sign-in screen');
  } on Transient catch (failure) {
    print('try again later: ${failure.cause}');
  }
}
```

## Where to go next

- [Concepts](concepts.md) — single-flight and sessions.
- [Streams](streams.md) — refresh on a long-lived stream.
