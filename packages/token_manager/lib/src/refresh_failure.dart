/// Why a token refresh failed; thrown by a `TokenRefresher`.
///
/// The two cases differ in what the session does next: [InvalidGrant] ends it,
/// [Transient] keeps it. Any other exception a refresher throws is treated as
/// [Transient].
///
/// {@category refreshing}
sealed class RefreshFailure implements Exception {
  /// Creates a failure.
  const RefreshFailure();
}

/// The refresh token was rejected for good: the user must sign in again.
///
/// The manager clears the store and emits `Unauthenticated`. Throw it only
/// when the server said the grant is dead, never for a network error.
///
/// {@category refreshing}
final class InvalidGrant extends RefreshFailure {
  /// Creates the failure.
  const InvalidGrant();

  @override
  String toString() => 'InvalidGrant: the refresh token was rejected';
}

/// The refresh failed for a reason that may go away, such as no network.
///
/// The session stays, and the next `TokenManager.validToken` retries.
///
/// {@category refreshing}
final class Transient extends RefreshFailure {
  /// Creates the failure wrapping what went wrong.
  const Transient(this.cause);

  /// What went wrong.
  final Object cause;

  @override
  String toString() => 'Transient: $cause';
}
