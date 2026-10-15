import '../token_refresher.dart';
import '../token_store.dart';
import 'refresh_attempt.dart';
import 'refresh_policy.dart';
import 'session.dart';

/// Starts the refreshes of one engine over the session's single flight.
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
