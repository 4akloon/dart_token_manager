import 'dart:async';

import 'auth_state.dart';
import 'clock.dart';
import 'engine/authorized_call.dart';
import 'engine/relay_stream.dart';
import 'engine/token_engine.dart';
import 'legacy/delegate_token_refresher.dart';
import 'legacy/storage_token_store.dart';
import 'token_info.dart';
import 'token_info_delegate.dart';
import 'token_manager_refresh_delegate.dart';
import 'token_refresher.dart';
import 'token_storage.dart';
import 'token_store.dart';

/// Manages the tokens of one session: storage, single-flight refresh and an
/// observable state.
class TokenManager<T> {
  /// Creates a manager from the old storage and delegates.
  @Deprecated('Use TokenManager.create.')
  TokenManager({
    required TokenStorage<T> storage,
    TokenManagerRefreshDelegate<T>? refreshDelegate,
    TokenInfoDelegate<T>? infoDelegate,
  }) : _engine = TokenEngine<T>(
         store: StorageTokenStore<T>(storage),
         skew: refreshDelegate?.refreshThreshold ?? const Duration(minutes: 3),
         clock: const Clock(),
         refresher: refreshDelegate == null
             ? null
             : DelegateTokenRefresher<T>(refreshDelegate),
         info: infoDelegate,
       );

  /// Creates a manager over [store].
  ///
  /// Tokens are refreshed with [refresher] when [info] says they expire within
  /// [skew], or when a server rejects them. Without a [refresher] tokens are
  /// never refreshed; without [info] they never expire.
  TokenManager.create({
    required TokenStore<T> store,
    TokenRefresher<T>? refresher,
    TokenInfo<T>? info,
    Duration skew = const Duration(seconds: 30),
    Clock clock = const Clock(),
  }) : _engine = TokenEngine<T>(
         store: store,
         skew: skew,
         clock: clock,
         refresher: refresher,
         info: info,
       );

  final TokenEngine<T> _engine;

  /// Emits the current state on listen, then every change.
  Stream<AuthState<T>> get states => _engine.states;

  /// Returns the current tokens without refreshing them.
  Future<T?> current() => _engine.current();

  /// Returns tokens that are valid now, refreshing them when needed.
  ///
  /// Pass the tokens a server just rejected as [rejected]. Concurrent callers
  /// share one refresh. Throws `NotAuthenticated` without tokens, `InvalidGrant`
  /// when the session ended, and `Transient` when the refresh may be retried.
  Future<T> validToken({T? rejected}) => _engine.validToken(rejected: rejected);

  /// Stores [tokens]; `null` signs out like [logout].
  Future<void> setTokens(T? tokens) =>
      tokens == null ? _engine.logout() : _engine.setTokens(tokens);

  /// Removes the tokens and signs the session out.
  Future<void> logout() => _engine.logout();

  /// Runs [send] with valid tokens, replaying it once after an auth failure.
  Future<R> authorize<R>(
    Future<R> Function(T tokens) send, {
    required bool Function(Object error) isAuthFailure,
  }) => AuthorizedCall<T>(_engine).run<R>(send, isAuthFailure: isAuthFailure);

  /// Opens a stream with valid tokens, reopening it once after an early auth
  /// failure. Pause, resume and cancel reach the source stream.
  Stream<R> authorizeStream<R>(
    Stream<R> Function(T tokens) open, {
    required bool Function(Object error) isAuthFailure,
  }) {
    return RelayStream<T, R>(
      acquire: validToken,
      renew: (rejected) => validToken(rejected: rejected),
      open: open,
      isAuthFailure: isAuthFailure,
    ).stream;
  }

  /// Releases the manager; work that finishes later is discarded.
  Future<void> dispose() => _engine.dispose();

  /// Returns the latest tokens, or `null` before they are loaded.
  @Deprecated('Use current() or states.')
  T? get tokens => _engine.state.tokensOrNull;

  /// Emits the tokens on every change; `null` means signed out.
  @Deprecated('Use states.')
  Stream<T?> get tokensStream =>
      _engine.states.map((state) => state.tokensOrNull);

  /// Loads the stored tokens.
  @Deprecated('Loading is lazy; use current().')
  Future<void> initialize() async {
    await _engine.current();
  }

  /// Forces a refresh; failures are swallowed.
  @Deprecated('Use validToken(rejected: ...).')
  Future<void> executeRefresh() async {
    final tokens = await _engine.current();
    if (tokens == null) {
      return;
    }
    try {
      await _engine.validToken(rejected: tokens);
    } on Exception catch (_) {
      // The old API never threw from a refresh; failures show in the state.
    }
  }

  /// Completes when the refresh in flight ends; `null` when none is running.
  @Deprecated('Use validToken().')
  Future<void>? get waitForFresh => _engine.pendingRefresh;
}
