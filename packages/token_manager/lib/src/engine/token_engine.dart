import 'dart:async';

import '../auth_state.dart';
import '../clock.dart';
import '../not_authenticated.dart';
import '../refresh_failure.dart';
import '../token_info.dart';
import '../token_refresher.dart';
import '../token_store.dart';
import 'replay_value.dart';

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
       _skew = skew,
       _clock = clock,
       _refresher = refresher,
       _info = info;

  final TokenStore<T> _store;
  final Duration _skew;
  final Clock _clock;
  final TokenRefresher<T>? _refresher;
  final TokenInfo<T>? _info;
  final ReplayValue<AuthState<T>> _states = ReplayValue<AuthState<T>>(
    Unauthenticated<T>(),
  );

  Future<void>? _loading;
  Future<void> _tail = Future<void>.value();
  Future<T>? _flight;
  int _epoch = 0;
  bool _disposed = false;

  /// Emits the latest state on listen, then every change.
  Stream<AuthState<T>> get states => _states.stream;

  /// The latest state.
  AuthState<T> get state => _states.value;

  /// Returns the current tokens without refreshing them.
  Future<T?> current() async {
    await _load();
    return state.tokensOrNull;
  }

  /// Returns tokens that are valid now, refreshing them when needed.
  ///
  /// [rejected] is a token a server just refused: it forces a refresh unless
  /// another caller already replaced it. Concurrent callers share one refresh.
  Future<T> validToken({T? rejected}) async {
    await _load();
    final tokens = state.tokensOrNull;
    if (tokens == null) {
      throw const NotAuthenticated();
    }
    final refresher = _refresher;
    if (refresher == null || !_needsRefresh(tokens, rejected)) {
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
    await _load();
    await _exclusive<void>(() async {
      await _store.write(tokens);
      _epoch++;
      _emit(Authenticated<T>(tokens));
    });
  }

  /// Removes the tokens and signs the session out.
  Future<void> logout() async {
    await _load();
    await _exclusive<void>(_clear);
  }

  /// Stops emitting; work that finishes later is discarded.
  Future<void> dispose() async {
    _disposed = true;
    _epoch++;
    await _states.close();
  }

  Future<void> _clear() async {
    await _store.delete();
    _epoch++;
    _emit(Unauthenticated<T>());
  }

  void _emit(AuthState<T> next) {
    if (_disposed) {
      return;
    }
    _states.add(next);
  }

  Future<void> _load() async {
    final loading = _loading ??= _loadOnce();
    try {
      await loading;
    } on Exception {
      if (identical(_loading, loading)) {
        _loading = null;
      }
      rethrow;
    }
  }

  Future<void> _loadOnce() async {
    final stored = await _store.read();
    if (stored != null) {
      _emit(Authenticated<T>(stored));
    }
  }

  bool _needsRefresh(T tokens, T? rejected) {
    return identical(tokens, rejected) || _isExpiring(tokens);
  }

  bool _isExpiring(T tokens) {
    final expiresAt = _info?.expiresAt(tokens);
    if (expiresAt == null) {
      return false;
    }
    return !_clock.now().add(_skew).isBefore(expiresAt);
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
    final T refreshed;
    try {
      refreshed = await refresher.refresh(current);
    } on InvalidGrant {
      await _exclusive<void>(() async {
        if (epoch == _epoch) {
          await _clear();
        }
      });
      rethrow;
    } on RefreshFailure {
      _restore(epoch, current);
      rethrow;
    } on Exception catch (error) {
      _restore(epoch, current);
      throw Transient(error);
    }
    final committed = await _commit(epoch, current, refreshed);
    return committed ?? _supersededBy();
  }

  /// Persists [refreshed] unless the session changed since [epoch].
  Future<T?> _commit(int epoch, T previous, T refreshed) {
    return _exclusive<T?>(() async {
      if (epoch != _epoch) {
        return null;
      }
      try {
        await _store.write(refreshed);
      } on Exception {
        _emit(Authenticated<T>(previous));
        rethrow;
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

  /// Runs [action] after every earlier exclusive action has finished.
  Future<R> _exclusive<R>(Future<R> Function() action) {
    final run = _tail.then<R>((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}
