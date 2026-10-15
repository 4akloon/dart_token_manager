import 'dart:async';

import '../token_refresher.dart';
import '../token_store.dart';
import 'refresh_attempt.dart';
import 'refresh_policy.dart';
import 'session.dart';

/// Starts the refreshes of one engine over the session's single flight: the
/// one a caller waits for and the one that runs ahead of expiry.
final class AheadRefresh<T> {
  /// Creates a starter that refreshes with [refresher] as [policy] decides.
  ///
  /// Without a [refresher] nothing is ever refreshed.
  AheadRefresh({
    required Session<T> session,
    required TokenStore<T> store,
    required RefreshPolicy<T> policy,
    TokenRefresher<T>? refresher,
  }) : _session = session,
       _store = store,
       _policy = policy,
       _refresher = refresher;

  final Session<T> _session;
  final TokenStore<T> _store;
  final RefreshPolicy<T> _policy;
  final TokenRefresher<T>? _refresher;

  // The tokens a background refresh was last started for: one attempt per
  // tokens object, so a failing server is not hit by every request.
  T? _attempted;

  /// The refresh [tokens] must wait for, or `null` when they can be used now.
  ///
  /// A refresh is due when [tokens] are the [rejected] ones or expire within
  /// the skew. It joins the refresh in flight, or starts one.
  Future<T>? dueFlight(T tokens, T? rejected) {
    final refresher = _refresher;
    if (refresher == null || !_policy.needsRefresh(tokens, rejected)) {
      return null;
    }
    return _flight(refresher, tokens);
  }

  /// Starts a background refresh of [tokens] when they are inside the window.
  ///
  /// Does nothing without a refresher or a window, after the session was
  /// disposed, while a refresh is in flight, or for tokens already tried. The
  /// refresh's failures are handled here: a failure that is an `Exception` is
  /// dropped (the attempt already restored the state, or ended the session on
  /// `InvalidGrant`); an `Error` is not caught.
  void startAhead(T tokens) {
    final refresher = _refresher;
    if (refresher == null ||
        _session.isClosed ||
        _session.flight != null ||
        identical(_attempted, tokens) ||
        !_policy.needsAheadRefresh(tokens)) {
      return;
    }
    _attempted = tokens;
    unawaited(
      _flight(refresher, tokens)
          .then<void>(_guardAgainstLoop)
          .catchError((_) {}, test: (error) => error is Exception),
    );
  }

  /// Marks tokens that a refresh returned inside the window as tried, so that
  /// a short-lived token does not start a refresh on every call.
  void _guardAgainstLoop(T refreshed) {
    if (_policy.needsAheadRefresh(refreshed)) {
      _attempted = refreshed;
    }
  }

  Future<T> _flight(TokenRefresher<T> refresher, T tokens) {
    final running = _session.flight;
    if (running != null) {
      return running;
    }
    final flight = RefreshAttempt<T>(
      session: _session,
      store: _store,
      refresher: refresher,
      current: tokens,
    ).run();
    _session.track(flight);
    return flight;
  }
}
