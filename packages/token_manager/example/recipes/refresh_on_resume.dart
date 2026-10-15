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
