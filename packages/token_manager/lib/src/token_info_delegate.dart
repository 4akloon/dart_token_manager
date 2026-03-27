/// Supplies metadata required to schedule proactive token refresh.
abstract interface class TokenInfoDelegate<T> {
  /// Returns the expiration time for the given tokens.
  ///
  /// Returns `null` if the tokens don't expire.
  DateTime? expiresAt(T tokens);
}
