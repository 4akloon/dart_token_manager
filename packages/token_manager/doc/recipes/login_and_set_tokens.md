# Recipe: sign in and store the tokens

Sign the user in against your token endpoint, hand the tokens to
`TokenManager.setTokens`, and let the manager refresh them from then on.
Use this when a Dart or Flutter app has an access token and a refresh token
and nothing yet that refreshes them.

## The code

`ApiRefresher` is the only place that talks to the refresh endpoint,
`Session` creates the one manager of the app, and `StandInAuthServer` lets
the file run without a network. Replace `AuthApi` with your HTTP client.

<!-- include: example/recipes/login_and_set_tokens.dart -->
```dart
import 'dart:io';

import 'package:token_manager/token_manager.dart';

/// What the token endpoint of your auth server answers.
typedef TokenResponse = ({
  String accessToken,
  String refreshToken,
  Duration expiresIn,
});

/// Turns a server answer into the tokens the manager stores.
extension TokenResponseTokens on TokenResponse {
  /// The tokens, expiring [expiresIn] from now.
  TokenSet toTokenSet() => TokenSet(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: DateTime.now().add(expiresIn),
  );
}

/// The server rejected the credentials or the refresh token for good.
final class GrantRejected implements Exception {
  /// Creates the exception.
  const GrantRejected();
}

/// Your auth server; implement it with the HTTP client you already use.
abstract interface class AuthApi {
  /// Exchanges an email and a password for tokens.
  Future<TokenResponse> signIn(String email, String password);

  /// Exchanges a refresh token for new tokens.
  Future<TokenResponse> refresh(String refreshToken);
}

/// Refreshes through [AuthApi]; the manager calls it, never your code.
final class ApiRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher over [api].
  const ApiRefresher(this._api);

  final AuthApi _api;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    final refreshToken = current.refreshToken;
    if (refreshToken == null) {
      throw const InvalidGrant();
    }
    try {
      return (await _api.refresh(refreshToken)).toTokenSet();
    } on GrantRejected {
      // The server said the refresh token is dead: the user must sign in
      // again. Any other exception, such as a network error, is Transient.
      throw const InvalidGrant();
    }
  }
}

/// One signed-in session: a manager plus the sign-in and sign-out calls.
final class Session {
  /// Creates a session over [api]; [store] defaults to memory.
  Session({required AuthApi api, TokenStore<TokenSet>? store})
    : _api = api,
      manager = TokenManager<TokenSet>.create(
        store: store ?? InMemoryTokenStore<TokenSet>(),
        refresher: ApiRefresher(api),
        info: const TokenSetInfo(),
      );

  /// The manager every adapter and repository shares.
  final TokenManager<TokenSet> manager;

  final AuthApi _api;

  /// Signs in and stores the tokens; throws [GrantRejected] on bad credentials.
  Future<void> signIn(String email, String password) async {
    final response = await _api.signIn(email, password);
    await manager.setTokens(response.toTokenSet());
  }

  /// Removes the tokens; the state becomes `Unauthenticated`.
  Future<void> signOut() => manager.logout();

  /// Releases the manager.
  Future<void> dispose() => manager.dispose();
}

// ---- Stand-in for your auth server, so this file runs without a network.

/// Answers like a token endpoint: any password but `wrong` signs in.
final class StandInAuthServer implements AuthApi {
  /// Creates a server whose access tokens live [lifetime].
  StandInAuthServer({this.lifetime = const Duration(hours: 1)});

  /// How long an issued access token lives.
  final Duration lifetime;

  /// When true, every refresh fails like a network error.
  bool isOffline = false;

  /// When true, the refresh token is rejected for good.
  bool isRevoked = false;

  /// How many refreshes reached the server.
  int refreshes = 0;

  TokenResponse _issue(int number) => (
    accessToken: 'access-$number',
    refreshToken: 'refresh-$number',
    expiresIn: lifetime,
  );

  @override
  Future<TokenResponse> signIn(String email, String password) async {
    if (password == 'wrong') {
      throw const GrantRejected();
    }
    return _issue(1);
  }

  @override
  Future<TokenResponse> refresh(String refreshToken) async {
    if (isOffline) {
      throw const SocketException('offline');
    }
    if (isRevoked) {
      throw const GrantRejected();
    }
    refreshes++;
    return _issue(refreshes + 1);
  }
}

Future<void> main() async {
  final session = Session(api: StandInAuthServer());

  await session.signIn('ada@example.com', 'correct horse');
  final tokens = await session.manager.validToken();
  stdout.writeln('Signed in with ${tokens.accessToken}');

  await session.signOut();
  stdout.writeln('Signed out: ${await session.manager.current() == null}');

  await session.dispose();
}
```

Run it with `dart run example/recipes/login_and_set_tokens.dart`. The test
`test/recipes/login_and_set_tokens_test.dart` checks every behaviour below.

## What you get

- `signIn` stores the tokens; wrong credentials leave the session signed out.
- Tokens that expire within the skew (30 seconds by default) are refreshed
  before `validToken()` or `authorize` returns them. Concurrent callers share
  one refresh.
- A rejected refresh token (`GrantRejected` here) becomes `InvalidGrant`: the
  manager signs the session out and `current()` returns `null`.
- A network failure becomes `Transient`: the session and its tokens stay, and
  the next call retries.

## Common mistakes

- **Forgetting `info: const TokenSetInfo()`.** Without a `TokenInfo` the
  manager treats tokens as never expiring and refreshes only after a server
  rejected them.
- **Throwing `InvalidGrant` for a network error.** It signs the user out. Throw
  it only when the server said the refresh token is dead.
- **Returning the old refresh token.** When the server rotates refresh tokens
  the answer carries a new one; return it, or the next refresh fails.
- **Creating a second manager for the same session.** Single-flight is per
  manager; two managers refresh twice. Share the one in `Session`.
- **Calling `setTokens` from the refresher.** The manager stores what
  `refresh` returns; `setTokens` is for sign-in.

## See also

- [Getting started](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/getting_started.md)
- [Refreshing and failures](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/refreshing.md)
