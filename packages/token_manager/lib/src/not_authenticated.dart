/// No tokens are available: the user is not signed in.
///
/// Thrown by `TokenManager.validToken` and `TokenManager.authorize` when there
/// is no session, and when a logout superseded the refresh being awaited.
///
/// {@category refreshing}
final class NotAuthenticated implements Exception {
  /// Creates the exception.
  const NotAuthenticated();

  @override
  String toString() => 'NotAuthenticated: there are no tokens';
}
