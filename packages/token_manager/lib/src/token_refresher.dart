/// Exchanges expiring tokens for fresh ones.
abstract interface class TokenRefresher<T> {
  /// Returns new tokens for [current].
  ///
  /// Throws `InvalidGrant` when the refresh token was rejected for good and
  /// `Transient` when the failure may go away. Any other exception is treated
  /// as transient.
  Future<T> refresh(T current);
}
