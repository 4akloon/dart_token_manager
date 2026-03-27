import 'dart:async';

import 'token_info_delegate.dart';
import 'token_manager_refresh_delegate.dart';
import 'token_storage.dart';
import 'token_store.dart';

/// Manages authentication tokens, including storage, refresh, and expiration handling.
///
/// This class provides functionality to:
/// - Store and retrieve tokens
/// - Automatically refresh tokens before they expire
/// - Handle token revocation
/// - Provide a stream of token updates
class TokenManager<T> {
  /// Creates a new [TokenManager] instance.
  ///
  /// The [storage] parameter is used to persist tokens.
  TokenManager({
    required TokenStorage<T> storage,
    TokenManagerRefreshDelegate<T>? refreshDelegate,
    TokenInfoDelegate<T>? infoDelegate,
  }) : _tokensStore = TokenStore(storage: storage),
       _refreshDelegate = refreshDelegate,
       _infoDelegate = infoDelegate;

  final TokenStore<T> _tokensStore;
  final TokenManagerRefreshDelegate<T>? _refreshDelegate;
  final TokenInfoDelegate<T>? _infoDelegate;

  Timer? _refreshTimer;
  Completer<void>? _refreshCompleter;

  /// Initializes the token manager by loading stored tokens.
  Future<void> initialize() => _tokensStore.initialize();

  /// Returns the current tokens.
  T? get tokens => _tokensStore.tokens;

  /// Stream of token updates.
  ///
  /// Emits `null` when tokens are cleared or revoked.
  Stream<T?> get tokensStream => _tokensStore.tokensStream;

  /// Executes a token refresh operation.
  ///
  /// If a refresh is already in progress, returns the future of the ongoing refresh.
  /// If tokens are revoked during refresh, they will be cleared.
  Future<void> executeRefresh() async {
    if (_refreshCompleter case final completer?) return completer.future;

    final tokens = _tokensStore.tokens;

    if (tokens == null) return;

    final refreshDelegate = _refreshDelegate;
    if (refreshDelegate == null) return;

    _resetTimer();

    _refreshCompleter = Completer();

    try {
      final refreshedTokens = await refreshDelegate.refresh(tokens);

      await setTokens(refreshedTokens);
    } on RevokedTokensException catch (_) {
      await setTokens(null);
    } catch (e) {
      _setTimer(DateTime.now().add(refreshDelegate.refreshDelay));
    } finally {
      _refreshCompleter?.complete();
      _refreshCompleter = null;
    }
  }

  /// Returns a future that completes when the current refresh operation finishes.
  Future<void>? get waitForFresh => _refreshCompleter?.future;

  /// Sets the current tokens and updates the refresh timer.
  ///
  /// If [tokens] is `null`, clears the stored tokens and cancels the refresh timer.
  Future<void> setTokens(T? tokens) async {
    await _tokensStore.setTokens(tokens);

    _resetTimer();

    if (tokens != null && _refreshDelegate != null) {
      final at = _infoDelegate?.expiresAt(tokens);

      if (at != null) _setTimer(at);
    }
  }

  Future<void> _setTimer(DateTime expiresAt) async {
    final refreshDelegate = _refreshDelegate;
    if (refreshDelegate == null) return;

    final duration =
        expiresAt.difference(DateTime.now()) - refreshDelegate.refreshThreshold;

    _resetTimer();
    if (duration.isNegative) {
      await executeRefresh();
    } else {
      _refreshTimer = Timer(duration, executeRefresh);
    }
  }

  void _resetTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Disposes of the token manager resources.
  ///
  /// This should be called when the token manager is no longer needed.
  Future<void> dispose() async {
    _resetTimer();
    await _tokensStore.dispose();

    if (_refreshCompleter != null) {
      _refreshCompleter?.complete();
      _refreshCompleter = null;
    }
  }
}

/// Exception thrown when tokens have been revoked and are no longer valid.
class RevokedTokensException implements Exception {
  /// Creates a revoked-tokens exception.
  const RevokedTokensException();
}
