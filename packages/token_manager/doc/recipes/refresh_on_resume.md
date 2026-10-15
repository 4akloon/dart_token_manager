# Recipe: refresh the session on app resume

Make sure the tokens are fresh when the app returns from the background, so
the first request after a long pause does not wait for a refresh.

## The code

`ResumeRefresh` is called from your lifecycle callback. In Flutter that is
`didChangeAppLifecycleState` when the state is `AppLifecycleState.resumed`.
`StandInRefresher` stands in for the token endpoint.

<!-- include: example/recipes/refresh_on_resume.dart -->
```dart
import 'dart:io';

import 'package:token_manager/token_manager.dart';

/// Refreshes the session when the app comes back to the foreground, so the
/// first request after a long pause does not wait for a refresh.
final class ResumeRefresh {
  /// Creates the helper over [_manager].
  const ResumeRefresh(this._manager);

  /// The margin used on resume: tokens that expire sooner are refreshed.
  static const Duration window = Duration(minutes: 10);

  final TokenManager<TokenSet> _manager;

  /// Call this from the app's lifecycle callback when it resumes.
  ///
  /// Tokens with less than [window] left are refreshed now. A network failure
  /// is ignored: the next request retries. A dead refresh token signs the
  /// session out, which a `states` listener already reports.
  Future<void> onResumed() async {
    try {
      await _manager.refreshIfNeeded(within: window);
    } on Transient {
      // Offline on resume is normal; the next request retries.
    } on InvalidGrant {
      // The session ended; the app reacts to `states`, not to this call.
    }
  }
}

// ---- Stand-in for the token endpoint, so this file runs without a server.

/// A refresher that counts its calls and can be told to fail.
final class StandInRefresher implements TokenRefresher<TokenSet> {
  /// Creates the refresher; with [failure] set, every call throws it.
  StandInRefresher({this.clock = const Clock(), this.failure});

  /// The clock that the lifetime of the new tokens is counted from.
  final Clock clock;

  /// What every call throws, or `null` to succeed.
  final RefreshFailure? failure;

  /// How many times [refresh] was called.
  int calls = 0;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    calls++;
    if (failure case final error?) {
      throw error;
    }
    return TokenSet(
      accessToken: 'access-$calls',
      refreshToken: 'refresh-$calls',
      expiresAt: clock.now().add(const Duration(hours: 1)),
    );
  }
}

Future<void> main() async {
  final refresher = StandInRefresher();
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: refresher,
    info: const TokenSetInfo(),
    refreshAhead: const Duration(minutes: 5),
  );
  // Eight minutes left: outside the five minute refreshAhead window, so
  // validToken would not refresh, but inside the ten minute resume window.
  await manager.setTokens(
    TokenSet(
      accessToken: 'access-0',
      refreshToken: 'refresh-0',
      expiresAt: DateTime.now().add(const Duration(minutes: 8)),
    ),
  );

  await ResumeRefresh(manager).onResumed();

  final tokens = await manager.current();
  stdout.writeln('Refreshed ${refresher.calls} time: ${tokens?.accessToken}');
  await manager.dispose();
}
```

Run it with `dart run example/recipes/refresh_on_resume.dart`. The test
`test/recipes/refresh_on_resume_test.dart` checks every behaviour below.

## What you get

- Tokens with less than ten minutes left are refreshed on resume, and the new
  tokens are stored. The ten minute window is larger than the five minute
  `refreshAhead` of the example, which acts only when a request asks for a
  token.
- Tokens with more time left are not touched, and the refresher is not called.
- A signed-out app does nothing: being signed out is not an error for
  `refreshIfNeeded`.
- An offline resume (`Transient`) keeps the session and does not throw; the
  next request retries.
- A dead refresh token (`InvalidGrant`) signs the session out and `onResumed`
  does not throw; a `states` listener, as in the session-expiry recipe,
  reports it.
- Two resumes at once share one refresh.

## Common mistakes

- **Waiting for it before the first frame.** `onResumed` can wait on the
  network. Start it without blocking the UI; the next request refreshes the
  tokens anyway if it has not finished.
- **Picking a window longer than the token lifetime.** Every resume then
  refreshes. Use a window of a few minutes, well below the lifetime.
- **Setting `refreshAhead` to `skew` or less.** `create` throws an
  `ArgumentError`; `refreshAhead` must be greater than `skew`.
- **Expecting a timer.** `refreshAhead` acts when a request asks for a token
  and `refreshIfNeeded` when you call it. A suspended app refreshes nothing,
  which is why the resume callback calls it.
- **Letting `Transient` escape.** `refreshIfNeeded` throws it to the caller;
  catch it where a failed refresh should not stop the app.

## See also

- [Refreshing before expiry](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/refreshing.md)
- [Send the user to sign-in when the session ends](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/recipes/session_expiry.md)
