import 'token_store.dart';

/// A [TokenStore] that keeps the tokens in memory only.
final class InMemoryTokenStore<T> implements TokenStore<T> {
  /// Creates a store, optionally holding [initial] tokens.
  InMemoryTokenStore([T? initial]) : _tokens = initial;

  T? _tokens;

  @override
  Future<T?> read() async => _tokens;

  @override
  Future<void> write(T tokens) async {
    _tokens = tokens;
  }

  @override
  Future<void> delete() async {
    _tokens = null;
  }
}
