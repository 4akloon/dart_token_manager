/// Tells when tokens expire.
///
/// The manager compares the answer with the clock and its skew to decide
/// whether `TokenManager.validToken` must refresh first.
///
/// ```dart
/// final class JwtInfo implements TokenInfo<String> {
///   const JwtInfo();
///
///   @override
///   DateTime? expiresAt(String jwt) => null; // decode the `exp` claim here
/// }
/// ```
///
/// {@category refreshing}
abstract interface class TokenInfo<T> {
  /// Returns when [tokens] expire, or `null` when they never do.
  DateTime? expiresAt(T tokens);
}
