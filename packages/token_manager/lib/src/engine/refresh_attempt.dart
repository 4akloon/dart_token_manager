import 'dart:async';

import '../auth_state.dart';
import '../not_authenticated.dart';
import '../refresh_failure.dart';
import '../token_refresher.dart';
import '../token_store.dart';
import 'session.dart';

/// One refresh of the current tokens, from the refresher call to the commit.
///
/// A [run] whose session changed in the meantime is discarded: it persists
/// nothing and resolves with whatever the new session holds.
final class RefreshAttempt<T> {
  /// Creates an attempt to refresh [current] with [refresher].
  RefreshAttempt({
    required Session<T> session,
    required TokenStore<T> store,
    required TokenRefresher<T> refresher,
    required T current,
  }) : _session = session,
       _store = store,
       _refresher = refresher,
       _current = current;

  final Session<T> _session;
  final TokenStore<T> _store;
  final TokenRefresher<T> _refresher;
  final T _current;

  /// Refreshes the tokens and returns the ones the session ends up with.
  Future<T> run() async {
    final epoch = _session.epoch;
    _session.emit(Refreshing<T>(_current));
    try {
      return await _attempt(epoch);
    } finally {
      // An Error from the refresher is not caught, but must not leave the
      // state stuck on Refreshing.
      if (epoch == _session.epoch && _session.state is Refreshing<T>) {
        _session.emit(Authenticated<T>(_current));
      }
    }
  }

  Future<T> _attempt(int epoch) async {
    final T refreshed;
    try {
      refreshed = await _refresher.refresh(_current);
    } on InvalidGrant {
      if (await _endSession(epoch)) {
        throw const InvalidGrant();
      }
      return _supersededBy();
    } on RefreshFailure catch (failure) {
      _restore(epoch);
      return _supersededOrThrow(epoch, failure);
    } on Exception catch (error) {
      _restore(epoch);
      return _supersededOrThrow(epoch, Transient(error));
    }
    final committed = await _commit(epoch, refreshed);
    return committed ?? _supersededBy();
  }

  /// Throws [failure] unless the session changed since [epoch]; a superseded
  /// refresh is discarded, failures included.
  T _supersededOrThrow(int epoch, RefreshFailure failure) {
    if (epoch != _session.epoch) {
      return _supersededBy();
    }
    throw failure;
  }

  /// Ends the session after a dead grant; false when it was already replaced.
  Future<bool> _endSession(int epoch) {
    return _session.queue.run<bool>(() async {
      if (epoch != _session.epoch) {
        return false;
      }
      try {
        await _store.delete();
      } on Exception {
        // The grant is dead, so the session ends even if the store could not
        // be cleaned; waiters still get InvalidGrant.
      }
      _session.startNewSession();
      _session.emit(Unauthenticated<T>());
      return true;
    });
  }

  /// Persists [refreshed] unless the session changed since [epoch].
  ///
  /// The server already rotated the old tokens, so a failed write still keeps
  /// [refreshed] as the in-memory state.
  Future<T?> _commit(int epoch, T refreshed) {
    return _session.queue.run<T?>(() async {
      if (epoch != _session.epoch) {
        return null;
      }
      try {
        await _store.write(refreshed);
      } on Exception {
        // Kept in memory only: nothing retries this write, the next refresh or
        // setTokens writes again.
      }
      _session.emit(Authenticated<T>(refreshed));
      return refreshed;
    });
  }

  void _restore(int epoch) {
    if (epoch == _session.epoch) {
      _session.emit(Authenticated<T>(_current));
    }
  }

  T _supersededBy() {
    final tokens = _session.state.tokensOrNull;
    if (tokens == null) {
      throw const NotAuthenticated();
    }
    return tokens;
  }
}
