/// Tells when tokens expire.
abstract interface class TokenInfo<T> {
  /// Returns when [tokens] expire, or `null` when they never do.
  DateTime? expiresAt(T tokens);
}
