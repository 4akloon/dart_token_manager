/// Defines how [TokenManager] refreshes expired tokens.
abstract class TokenManagerRefreshDelegate<T> {
  /// Creates a refresh delegate.
  const TokenManagerRefreshDelegate();

  /// Refreshes the provided tokens.
  ///
  /// This method should be implemented to handle the actual token refresh logic.
  /// If the tokens are revoked, throw [RevokedTokensException].
  Future<T> refresh(T tokens);

  /// Time before expiration when refresh should be scheduled.
  Duration get refreshThreshold => const Duration(minutes: 3);

  /// Delay before retrying refresh after a transient failure.
  Duration get refreshDelay => const Duration(minutes: 3);
}
