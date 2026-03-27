import 'package:rxdart/rxdart.dart';

import 'token_storage.dart';

/// Internal token state holder backed by [TokenStorage].
class TokenStore<T> {
  /// Creates a store instance and seeds stream with `null`.
  TokenStore({required TokenStorage<T> storage})
    : _storage = storage,
      _tokensSubject = BehaviorSubject.seeded(null);

  final TokenStorage<T> _storage;
  final BehaviorSubject<T?> _tokensSubject;

  /// Returns currently cached tokens.
  T? get tokens => _tokensSubject.value;

  /// Emits every token change, including `null` when cleared.
  Stream<T?> get tokensStream => _tokensSubject.stream;

  /// Loads persisted tokens and publishes them to subscribers.
  Future<void> initialize() async {
    final initialTokens = await _storage.getTokens();

    await setTokens(initialTokens);
  }

  /// Updates memory cache and persists tokens.
  Future<void> setTokens(T? tokens) async {
    if (_tokensSubject.isClosed) return;

    _tokensSubject.add(tokens);

    await _storage.setTokens(tokens);
  }

  /// Closes internal stream resources.
  Future<void> dispose() => _tokensSubject.close();
}
