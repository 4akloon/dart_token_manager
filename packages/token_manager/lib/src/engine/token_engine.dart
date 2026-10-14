import 'dart:async';

import '../auth_state.dart';
import '../clock.dart';
import '../not_authenticated.dart';
import '../refresh_failure.dart';
import '../token_info.dart';
import '../token_refresher.dart';
import '../token_store.dart';
import 'refresh_policy.dart';
import 'replay_value.dart';
import 'serial_queue.dart';
import 'stored_tokens_loader.dart';

/// Loads, persists and refreshes the tokens of one session.
///
/// `TokenManager` delegates all of its work here.
final class TokenEngine<T> {
  /// Creates an engine over [store].
  TokenEngine({
    required TokenStore<T> store,
    required Duration skew,
    required Clock clock,
    TokenRefresher<T>? refresher,
    TokenInfo<T>? info,
  }) : _store = store,
       _refresher = refresher,
       _policy = RefreshPolicy<T>(skew: skew, clock: clock, info: info);

  final TokenStore<T> _store;
  final TokenRefresher<T>? _refresher;
  final RefreshPolicy<T> _policy;
  final SerialQueue _queue = SerialQueue();
  final ReplayValue<AuthState<T>> _states = ReplayValue<AuthState<T>>(
    Unauthenticated<T>(),
  );

  // late: the loader's callbacks read this engine's epoch and emit its state.
  late final StoredTokensLoader<T> _loader = StoredTokensLoader<T>(
    store: _store,
    epoch: () => _epoch,
    onLoaded: (tokens) => _emit(Authenticated<T>(tokens)),
  );

  Future<T>? _flight;
  int _epoch = 0;

  /// Emits the latest state on listen, then every change.
  Stream<AuthState<T>> get states => _states.stream;

  /// The latest state.
  AuthState<T> get state => _states.value;

  /// Returns the current tokens without refreshing them.
  Future<T?> current() async {
    await _loader.load();
    return state.tokensOrNull;
  }

  /// Returns tokens that are valid now, refreshing them when needed.
  ///
  /// [rejected] is a token a server just refused: it forces a refresh unless
  /// another caller already replaced it. Concurrent callers share one refresh.
  Future<T> validToken({T? rejected}) async {
    await _loader.load();
    final tokens = state.tokensOrNull;
    if (tokens == null) {
      throw const NotAuthenticated();
    }
    final refresher = _refresher;
    if (refresher == null || !_policy.needsRefresh(tokens, rejected)) {
      return tokens;
    }
    final running = _flight;
    if (running != null) {
      return running;
    }
    final flight = _refresh(refresher, tokens);
    _flight = flight;
    _forgetWhenDone(flight);
    return flight;
  }

  /// Completes when the refresh in flight ends, never with an error; `null`
  /// when no refresh is running.
  Future<void>? get pendingRefresh =>
      _flight?.then<void>((_) {}, onError: (_) {});

  /// Stores [tokens] and makes them the current session.
  Future<void> setTokens(T tokens) async {
    await _loader.loadUnlessBroken();
    await _queue.run<void>(() async {
      await _store.write(tokens);
      _loader.markLoaded();
      _startNewSession();
      _emit(Authenticated<T>(tokens));
    });
  }

  /// Removes the tokens and signs the session out.
  Future<void> logout() async {
    await _loader.loadUnlessBroken();
    await _queue.run<void>(_clear);
  }

  /// Closes [states]; a refresh that finishes later is still persisted.
  ///
  /// [state] keeps following every change, but nothing is emitted any more.
  Future<void> dispose() async {
    await _states.close();
  }

  Future<void> _clear() async {
    await _store.delete();
    _loader.markLoaded();
    _startNewSession();
    _emit(Unauthenticated<T>());
  }

  /// Invalidates work started for the previous session, flight included.
  ///
  /// The old flight keeps running so that its own waiters still resolve.
  void _startNewSession() {
    _epoch++;
    _flight = null;
  }

  void _emit(AuthState<T> next) {
    _states.add(next);
  }

  void _forgetWhenDone(Future<T> flight) {
    void forget() {
      if (identical(_flight, flight)) {
        _flight = null;
      }
    }

    flight.then<void>((_) => forget(), onError: (_) => forget());
  }

  Future<T> _refresh(TokenRefresher<T> refresher, T current) async {
    final epoch = _epoch;
    _emit(Refreshing<T>(current));
    try {
      return await _attempt(refresher, current, epoch);
    } finally {
      // An Error from the refresher is not caught, but must not leave the
      // state stuck on Refreshing.
      if (epoch == _epoch && state is Refreshing<T>) {
        _emit(Authenticated<T>(current));
      }
    }
  }

  Future<T> _attempt(TokenRefresher<T> refresher, T current, int epoch) async {
    final T refreshed;
    try {
      refreshed = await refresher.refresh(current);
    } on InvalidGrant {
      if (await _endSession(epoch)) {
        throw const InvalidGrant();
      }
      return _supersededBy();
    } on RefreshFailure catch (failure) {
      _restore(epoch, current);
      return _supersededOrThrow(epoch, failure);
    } on Exception catch (error) {
      _restore(epoch, current);
      return _supersededOrThrow(epoch, Transient(error));
    }
    final committed = await _commit(epoch, refreshed);
    return committed ?? _supersededBy();
  }

  /// Throws [failure] unless the session changed since [epoch]; a superseded
  /// refresh is discarded, failures included.
  T _supersededOrThrow(int epoch, RefreshFailure failure) {
    if (epoch != _epoch) {
      return _supersededBy();
    }
    throw failure;
  }

  /// Ends the session after a dead grant; false when it was already replaced.
  Future<bool> _endSession(int epoch) {
    return _queue.run<bool>(() async {
      if (epoch != _epoch) {
        return false;
      }
      try {
        await _store.delete();
      } on Exception {
        // The grant is dead, so the session ends even if the store could not
        // be cleaned; waiters still get InvalidGrant.
      }
      _startNewSession();
      _emit(Unauthenticated<T>());
      return true;
    });
  }

  /// Persists [refreshed] unless the session changed since [epoch].
  ///
  /// The server already rotated the old tokens, so a failed write still keeps
  /// [refreshed] as the in-memory state.
  Future<T?> _commit(int epoch, T refreshed) {
    return _queue.run<T?>(() async {
      if (epoch != _epoch) {
        return null;
      }
      try {
        await _store.write(refreshed);
      } on Exception {
        // Kept in memory only: nothing retries this write, the next refresh or
        // setTokens writes again.
      }
      _emit(Authenticated<T>(refreshed));
      return refreshed;
    });
  }

  void _restore(int epoch, T current) {
    if (epoch == _epoch) {
      _emit(Authenticated<T>(current));
    }
  }

  T _supersededBy() {
    final tokens = state.tokensOrNull;
    if (tokens == null) {
      throw const NotAuthenticated();
    }
    return tokens;
  }
}
