/// Exception thrown when tokens have been revoked and are no longer valid.
@Deprecated('Throw InvalidGrant from a TokenRefresher instead.')
class RevokedTokensException implements Exception {
  /// Creates a revoked-tokens exception.
  @Deprecated('Throw InvalidGrant from a TokenRefresher instead.')
  const RevokedTokensException();
}
