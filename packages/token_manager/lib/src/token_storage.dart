import 'dart:async';

/// Interface for storing and retrieving authentication tokens.
///
/// This interface defines the contract for token storage implementations.
/// Implementations should handle the persistence of tokens in a secure manner.
abstract interface class TokenStorage<T> {
  /// Retrieves the stored tokens.
  ///
  /// Returns `null` if no tokens are stored.
  FutureOr<T?> getTokens();

  /// Stores the provided tokens.
  ///
  /// If [tokens] is `null`, the stored tokens should be cleared.
  Future<void> setTokens(T? tokens);
}
