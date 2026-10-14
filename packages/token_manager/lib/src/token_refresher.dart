/// Exchanges expiring tokens for fresh ones.
///
/// The manager decides when to call it and guarantees one call at a time per
/// session; the implementation only talks to the token endpoint.
///
/// ```dart
/// final class HttpRefresher implements TokenRefresher<TokenSet> {
///   @override
///   Future<TokenSet> refresh(TokenSet current) async {
///     // Post current.refreshToken; throw InvalidGrant on a 400.
///     return TokenSet(accessToken: 'new', refreshToken: 'new-refresh');
///   }
/// }
/// ```
///
/// {@category refreshing}
abstract interface class TokenRefresher<T> {
  /// Returns new tokens for [current].
  ///
  /// Throws `InvalidGrant` when the refresh token was rejected for good and
  /// `Transient` when the failure may go away. Any other exception is treated
  /// as transient.
  Future<T> refresh(T current);
}
