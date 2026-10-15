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

With `refreshAhead` set, `validToken` also starts a background refresh for
tokens that are close to expiry; see below.

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

## Refreshing before expiry

`skew` is the margin below which `validToken` waits for a refresh.
`refreshAhead` is a second, larger margin: tokens that are valid but expire
within it are returned at once and refreshed in the background.

| Time left | Default | With `refreshAhead` |
|---|---|---|
| more than `refreshAhead` | return | return |
| between `skew` and `refreshAhead` | return | return, and refresh in the background |
| less than `skew` | refresh and wait | refresh and wait |

```dart
import 'package:token_manager/token_manager.dart';

final aheadManager = TokenManager<TokenSet>.create(
  store: InMemoryTokenStore<TokenSet>(),
  refresher: HttpRefresher(),
  info: const TokenSetInfo(),
  skew: const Duration(seconds: 30),
  refreshAhead: const Duration(minutes: 5),
);
```

`refreshAhead` is `null` by default, which turns it off. It must be greater
than `skew`, or `create` throws an `ArgumentError`. Choose it well below the
lifetime of your tokens. Each tokens object gets one background attempt, however
it arrived: a blocking refresh, `refreshIfNeeded` or `setTokens` can all produce
tokens already inside the window, and the next `validToken` then starts one
refresh for them. A window longer than the token lifetime therefore refreshes
about twice as often as needed. The blocking path takes over at `skew`.

The background refresh follows these rules:

- **Single flight.** It is the session's one refresh. A caller that arrives
  during it and needs a refresh (less than `skew` left, or a rejected token)
  awaits it like any other.
- **One attempt per tokens object.** After a failed background attempt the
  manager does not try again for the same tokens, so a failing server is not
  hit by every request. When the tokens reach `skew`, the blocking refresh
  retries as usual.
- **Failures stay quiet.** `Transient`, or any other `Exception`, is dropped:
  the state returns to `Authenticated` and nothing is thrown. `InvalidGrant`
  ends the session as it always does: the store is cleared and `states` emits
  `Unauthenticated`. An `Error` is never caught.
- **Sessions are respected.** `setTokens` and `logout` discard
  the result of a running background refresh. `dispose` does not: a rotated
  refresh token is not lost. After `dispose` no new background refresh starts.

### refreshIfNeeded

`refreshIfNeeded` refreshes at a moment you choose and waits for it:

```dart
Future<void> onStart(TokenManager<TokenSet> manager) async {
  try {
    await manager.refreshIfNeeded(within: const Duration(minutes: 10));
  } on Transient {
    // Offline at start-up is normal; the next request retries.
  }
}
```

`within` defaults to `refreshAhead`, or to `skew` when it is not set. With no
tokens, no refresher, or enough time left, it completes without calling the
refresher; being signed out is not an error here. When a refresh is needed it
awaits the single flight and throws `InvalidGrant` or `Transient` to the
caller. It never reports a rejected token; that stays in `validToken`.

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
