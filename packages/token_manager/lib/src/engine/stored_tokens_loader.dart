import 'dart:async';

import '../token_store.dart';

/// Reads the stored tokens once and hands them to a callback.
///
/// A failed read is not remembered: the next [load] reads again.
final class StoredTokensLoader<T> {
  /// Creates a loader over [store].
  ///
  /// [epoch] tells the current session; a read that finishes after it changed
  /// is dropped. [onLoaded] receives the tokens of a read that is kept.
  StoredTokensLoader({
    required TokenStore<T> store,
    required int Function() epoch,
    required void Function(T tokens) onLoaded,
  }) : _store = store,
       _epoch = epoch,
       _onLoaded = onLoaded;

  final TokenStore<T> _store;
  final int Function() _epoch;
  final void Function(T tokens) _onLoaded;
  Future<void>? _loading;

  /// Loads the stored tokens once; concurrent callers share the read.
  Future<void> load() async {
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

  /// Loads the stored tokens, ignoring a read failure.
  ///
  /// The write that follows supersedes whatever the store held.
  Future<void> loadUnlessBroken() async {
    try {
      await load();
    } on Exception {
      // current() and validToken() surface the read error themselves.
    }
  }

  /// Treats the store as read: the loader now knows what it holds.
  void markLoaded() {
    _loading = Future<void>.value();
  }

  Future<void> _loadOnce() async {
    final epoch = _epoch();
    final stored = await _store.read();
    // setTokens and logout bump the epoch; their state is newer than this read.
    if (stored != null && epoch == _epoch()) {
      _onLoaded(stored);
    }
  }
}
