/// No tokens are available: the user is not signed in.
final class NotAuthenticated implements Exception {
  /// Creates the exception.
  const NotAuthenticated();

  @override
  String toString() => 'NotAuthenticated: there are no tokens';
}
