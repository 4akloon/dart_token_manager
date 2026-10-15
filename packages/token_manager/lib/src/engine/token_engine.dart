import 'dart:async';

import '../auth_state.dart';
import '../not_authenticated.dart';
import '../token_refresher.dart';
import '../token_store.dart';
import 'ahead_refresh.dart';
import 'refresh_policy.dart';
import 'session.dart';
import 'stored_tokens_loader.dart';

/// Loads, persists and refreshes the tokens of one session.
///
/// `TokenManager` delegates all of its work here.
final class TokenEngine<T> {
  /// Creates an engine over [store] that refreshes as [policy] decides.
  TokenEngine({
    required TokenStore<T> store,
    required RefreshPolicy<T> policy,
    TokenRefresher<T>? refresher,
  }) : _store = store {
    _refresh = AheadRefresh<T>(
      session: _session,
      store: store,
      policy: policy,
      refresher: refresher,
    );
  }

  final TokenStore<T> _store;
  final Session<T> _session = Session<T>();

  // late: it reads this engine's session, which exists only after the
  // initializer list has run.
  late final AheadRefresh<T> _refresh;

  // late: the loader's callbacks read this engine's session.
  late final StoredTokensLoader<T> _loader = StoredTokensLoader<T>(
    store: _store,
    epoch: () => _session.epoch,
    onLoaded: (tokens) => _session.emit(Authenticated<T>(tokens)),
  );

  /// Emits the latest state on listen, then every change.
  Stream<AuthState<T>> get states => _session.states;

  /// The latest state.
  AuthState<T> get state => _session.state;

  /// Returns the current tokens without refreshing them.
  Future<T?> current() async {
    await _loader.load();
    return state.tokensOrNull;
  }

  /// Returns tokens that are valid now, refreshing them when needed.
  ///
  /// [rejected] is a token a server just refused: it forces a refresh unless
  /// another caller already replaced it. Concurrent callers share one refresh.
  /// Tokens that are valid but inside the refresh-ahead window are returned at
  /// once and refreshed in the background.
  Future<T> validToken({T? rejected}) async {
    await _loader.load();
    final tokens = state.tokensOrNull;
    if (tokens == null) {
      throw const NotAuthenticated();
    }
    final due = _refresh.dueFlight(tokens, rejected);
    if (due != null) {
      return due;
    }
    _refresh.startAhead(tokens);
    return tokens;
  }

  /// Completes when the refresh in flight ends, never with an error; `null`
  /// when no refresh is running.
  Future<void>? get pendingRefresh =>
      _session.flight?.then<void>((_) {}, onError: (_) {});

  /// Stores [tokens] and makes them the current session.
  Future<void> setTokens(T tokens) async {
    await _loader.loadUnlessBroken();
    await _session.queue.run<void>(() async {
      await _store.write(tokens);
      _loader.markLoaded();
      _session.startNewSession();
      _session.emit(Authenticated<T>(tokens));
    });
  }

  /// Removes the tokens and signs the session out.
  Future<void> logout() async {
    await _loader.loadUnlessBroken();
    await _session.queue.run<void>(_clear);
  }

  /// Closes [states]; a refresh that finishes later is still persisted.
  ///
  /// [state] keeps following every change, but nothing is emitted any more.
  Future<void> dispose() async {
    await _session.close();
  }

  Future<void> _clear() async {
    await _store.delete();
    _loader.markLoaded();
    _session.startNewSession();
    _session.emit(Unauthenticated<T>());
  }
}
