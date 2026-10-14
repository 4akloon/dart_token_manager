import 'token_manager.dart';

/// Holds one [TokenManager] per provider id, each with its own token type.
final class TokenManagerRegistry {
  /// Creates an empty registry.
  TokenManagerRegistry();

  final Map<String, TokenManager<Object?>> _managers = {};

  /// The ids of the registered managers.
  Iterable<String> get ids => _managers.keys;

  /// Registers [manager] under [id].
  ///
  /// Throws a [StateError] when [id] is already taken.
  void register<T>(String id, TokenManager<T> manager) {
    if (_managers.containsKey(id)) {
      throw StateError('A token manager is already registered for "$id".');
    }
    _managers[id] = manager;
  }

  /// Returns the manager registered under [id].
  ///
  /// Throws a [StateError] when there is none, or when it handles another
  /// token type than [T].
  TokenManager<T> get<T>(String id) {
    final manager = _managers[id];
    if (manager == null) {
      throw StateError('No token manager is registered for "$id".');
    }
    if (manager is! TokenManager<T>) {
      throw StateError(
        'The token manager for "$id" has a different token type than $T.',
      );
    }
    return manager;
  }

  /// Disposes every manager and empties the registry.
  Future<void> dispose() async {
    for (final manager in _managers.values) {
      await manager.dispose();
    }
    _managers.clear();
  }
}
