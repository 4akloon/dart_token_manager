/// Why a token refresh failed; thrown by a `TokenRefresher`.
sealed class RefreshFailure implements Exception {
  /// Creates a failure.
  const RefreshFailure();
}

/// The refresh token was rejected for good: the user must sign in again.
final class InvalidGrant extends RefreshFailure {
  /// Creates the failure.
  const InvalidGrant();

  @override
  String toString() => 'InvalidGrant: the refresh token was rejected';
}

/// The refresh failed for a reason that may go away, such as no network.
final class Transient extends RefreshFailure {
  /// Creates the failure wrapping what went wrong.
  const Transient(this.cause);

  /// What went wrong.
  final Object cause;

  @override
  String toString() => 'Transient: $cause';
}
