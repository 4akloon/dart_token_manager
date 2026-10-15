import 'dart:async';

import 'auth_state.dart';
import 'clock.dart';
import 'engine/authorized_call.dart';
import 'engine/refresh_policy.dart';
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
///
/// Refresh is on demand: tokens are refreshed when [validToken], [authorize],
/// [refreshIfNeeded] or a rejected token asks for it, and, when `refreshAhead`
/// is set, in the background just before they expire. There is no timer.
/// Concurrent callers share one refresh.
///
/// ```dart
/// final manager = TokenManager<TokenSet>.create(
///   store: InMemoryTokenStore<TokenSet>(),
///   refresher: MyRefresher(),
///   info: const TokenSetInfo(),
/// );
/// await manager.setTokens(tokens);
/// final valid = await manager.validToken();
/// ```
///
/// {@category getting-started}
/// {@category streams}
class TokenManager<T> {
  /// Creates a manager from the old storage and delegates.
  @Deprecated('Use TokenManager.create.')
  TokenManager({
    required TokenStorage<T> storage,
    TokenManagerRefreshDelegate<T>? refreshDelegate,
    TokenInfoDelegate<T>? infoDelegate,
  }) : _engine = TokenEngine<T>(
         store: StorageTokenStore<T>(storage),
         policy: RefreshPolicy<T>(
           skew:
               refreshDelegate?.refreshThreshold ?? const Duration(minutes: 3),
           clock: const Clock(),
           info: infoDelegate,
         ),
         refresher: refreshDelegate == null
             ? null
             : DelegateTokenRefresher<T>(refreshDelegate),
       );

  /// Creates a manager over [store].
  ///
  /// Tokens are refreshed with [refresher] when [info] says they expire within
  /// [skew], or when a server rejects them. With [refreshAhead] set, tokens
  /// that expire within it are also refreshed in the background by the next
  /// [validToken]; it must be greater than [skew], or an [ArgumentError] is
  /// thrown. Without a [refresher] tokens are never refreshed; without [info]
  /// they never expire.
  TokenManager.create({
    required TokenStore<T> store,
    TokenRefresher<T>? refresher,
    TokenInfo<T>? info,
    Duration skew = const Duration(seconds: 30),
    Duration? refreshAhead,
    Clock clock = const Clock(),
  }) : _engine = TokenEngine<T>(
         store: store,
         policy: RefreshPolicy<T>(
           skew: skew,
           refreshAhead: refreshAhead,
           clock: clock,
           info: info,
         ),
         refresher: refresher,
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
  /// With refreshAhead set, tokens that are close to expiry are returned at
  /// once and refreshed in the background.
  Future<T> validToken({T? rejected}) => _engine.validToken(rejected: rejected);

  /// Refreshes the tokens when less than [within] is left before they expire.
  ///
  /// Use it at a moment you choose, such as start-up or app resume, to have
  /// fresh tokens before the first request. [within] defaults to the
  /// `refreshAhead` given to [TokenManager.create], or to its `skew` when none
  /// was given; pass a larger value, for example `Duration(minutes: 10)`, to
  /// refresh earlier. Completes normally without tokens, without a refresher
  /// and when enough time is left. A refresh that is needed is awaited through
  /// the single flight and its `InvalidGrant` or `Transient` is thrown to the
  /// caller.
  ///
  /// Tokens without an expiry (no `info`, or an `expiresAt` of null) are never
  /// refreshed. A [within] of zero or less refreshes only tokens that are
  /// already expired.
  Future<void> refreshIfNeeded({Duration? within}) =>
      _engine.refreshIfNeeded(within: within);

  /// Stores [tokens]; `null` signs out like [logout].
  Future<void> setTokens(T? tokens) =>
      tokens == null ? _engine.logout() : _engine.setTokens(tokens);

  /// Removes the tokens and signs the session out.
  Future<void> logout() => _engine.logout();

  /// Runs [send] with valid tokens, replaying it once after an auth failure.
  ///
  /// [send] runs once per attempt, at most twice. An exception it throws,
  /// synchronously or through its future, fails that attempt like a failed
  /// call.
  Future<R> authorize<R>(
    Future<R> Function(T tokens) send, {
    required bool Function(Object error) isAuthFailure,
  }) => AuthorizedCall<T>(_engine).run<R>(send, isAuthFailure: isAuthFailure);

  /// Opens a stream with valid tokens, reopening it once after an early auth
  /// failure. Pause, resume and cancel reach the source stream.
  ///
  /// Nothing is opened until the stream is listened to. [open] runs once per
  /// attempt, at most twice, and never after the listener cancelled. An
  /// exception that [open] throws becomes the stream's error and ends it.
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
      _engine.states.map((state) => state.tokensOrNull).distinct(identical);

  /// Loads the stored tokens.
  @Deprecated('Loading is lazy; use current().')
  Future<void> initialize() async {
    await _engine.current();
  }

  /// Forces a refresh; failures that are exceptions are swallowed.
  @Deprecated('Use validToken(rejected: ...).')
  Future<void> executeRefresh() async {
    final tokens = await _engine.current();
    if (tokens == null) {
      return;
    }
    try {
      await _engine.validToken(rejected: tokens);
    } on Exception catch (_) {
      // Exceptions show in the state. 0.1 caught everything (`catch (e)`); an
      // Error, such as a TypeError from a delegate, now propagates.
    }
  }

  /// Completes when the refresh in flight ends; `null` when none is running.
  @Deprecated('Use validToken().')
  Future<void>? get waitForFresh => _engine.pendingRefresh;
}
