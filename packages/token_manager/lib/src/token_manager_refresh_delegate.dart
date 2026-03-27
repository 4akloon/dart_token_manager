abstract class TokenManagerRefreshDelegate<T> {
  const TokenManagerRefreshDelegate();

  /// Refreshes the provided tokens.
  ///
  /// This method should be implemented to handle the actual token refresh logic.
  /// If the tokens are revoked, throw [RevokedTokensException].
  Future<T> refresh(T tokens);

  Duration get refreshThreshold => const Duration(minutes: 3);

  Duration get refreshDelay => const Duration(minutes: 3);
}
