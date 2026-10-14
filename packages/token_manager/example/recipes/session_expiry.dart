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
