# Recipe: send the user to sign-in when the session ends

React to logout and to a dead refresh token from one place, the `states`
stream, instead of catching `InvalidGrant` around every call.

## The code

`SessionWatcher` listens to `TokenManager.states` and calls your callback when
a signed-in session ends. `RevokedRefresher` stands in for a server that has
revoked the session.

<!-- include: example/recipes/session_expiry.dart -->
```dart
import 'dart:async';
import 'dart:io';

import 'package:token_manager/token_manager.dart';

/// Tells the app when a signed-in session ends, so it can show the sign-in
/// screen.
///
/// The session ends when the refresh token is rejected for good
/// (`InvalidGrant`) or when the app calls `logout`. A failed refresh that may
/// go away (`Transient`) does not end it.
final class SessionWatcher {
  /// Creates a watcher over [_manager].
  SessionWatcher(this._manager);

  final TokenManager<TokenSet> _manager;
  StreamSubscription<AuthState<TokenSet>>? _subscription;

  /// Calls [onSignedOut] each time a signed-in session ends.
  ///
  /// `states` replays the current state to a new listener, so the first
  /// `Unauthenticated` of an app that starts signed out is not reported.
  void watch({required void Function() onSignedOut}) {
    var wasSignedIn = false;
    _subscription = _manager.states.listen((state) {
      switch (state) {
        case Unauthenticated<TokenSet>():
          if (wasSignedIn) {
            wasSignedIn = false;
            onSignedOut();
          }
        case Authenticated<TokenSet>() || Refreshing<TokenSet>():
          wasSignedIn = true;
      }
    });
  }

  /// Stops watching.
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

// ---- Stand-in for a revoked session, so this file runs without a server.

/// A refresher whose server has revoked the session.
final class RevokedRefresher implements TokenRefresher<TokenSet> {
  /// Creates the refresher.
  const RevokedRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    throw const InvalidGrant();
  }
}

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: const RevokedRefresher(),
    info: const TokenSetInfo(),
  );
  final watcher = SessionWatcher(manager)
    ..watch(onSignedOut: () => stdout.writeln('Show the sign-in screen'));

  await manager.setTokens(
    TokenSet(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(seconds: 5)),
    ),
  );
  try {
    await manager.validToken();
  } on InvalidGrant {
    stdout.writeln('The refresh token was rejected');
  }
  await Future<void>.delayed(Duration.zero);

  await watcher.close();
  await manager.dispose();
}
```

Run it with `dart run example/recipes/session_expiry.dart`. The test
`test/recipes/session_expiry_test.dart` checks every behaviour below.

## What you get

- An app that starts signed out is not reported: `states` replays the current
  state to a new listener, and the watcher ignores an `Unauthenticated` that
  did not follow a signed-in state.
- A rejected refresh token (`InvalidGrant`) ends the session and calls the
  callback once.
- `logout()` calls the callback once, however often it is called.
- A `Transient` refresh failure keeps the session and does not call it.

## Common mistakes

- **Treating the first `Unauthenticated` as an expiry.** It is the replay of
  the initial state; the login screen would flash at start-up.
- **Treating `Refreshing` as signed out.** The session is still valid while a
  refresh runs.
- **Expecting a timer.** There is none: a session that dies while the app is
  idle is noticed on the next `validToken`, `authorize` or `refreshIfNeeded`.
  To check at a moment you choose, such as app resume, call `refreshIfNeeded`.
- **Navigating from inside a `TokenRefresher`.** The refresher only talks to the
  token endpoint; navigation belongs in the state listener.
- **Forgetting `close()`.** Cancel the subscription when the screen or scope
  that owns the watcher goes away.

## See also

- [Concepts and session state](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/concepts.md)
- [Streams](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/streams.md)
