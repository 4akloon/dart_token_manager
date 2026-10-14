// The legacy adapters implement the deprecated API on purpose.
// ignore_for_file: deprecated_member_use_from_same_package

import '../token_storage.dart';
import '../token_store.dart';

/// Adapts the old [TokenStorage] to a [TokenStore].
final class StorageTokenStore<T> implements TokenStore<T> {
  /// Creates a store over [storage].
  const StorageTokenStore(this._storage);

  final TokenStorage<T> _storage;

  @override
  Future<T?> read() async => _storage.getTokens();

  @override
  Future<void> write(T tokens) => _storage.setTokens(tokens);

  @override
  Future<void> delete() => _storage.setTokens(null);
}
