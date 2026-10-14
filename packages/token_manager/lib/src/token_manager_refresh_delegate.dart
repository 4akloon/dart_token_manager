/// Defines how [TokenManager] refreshes expired tokens.
///
/// {@category migration}
@Deprecated(
  'Use TokenRefresher; set the expiry margin with '
  'TokenManager.create(skew: ...).',
)
abstract class TokenManagerRefreshDelegate<T> {
  /// Creates a refresh delegate.
  @Deprecated(
    'Use TokenRefresher; set the expiry margin with '
    'TokenManager.create(skew: ...).',
  )
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
