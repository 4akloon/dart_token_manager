/// Persists the tokens of one session; the core does no platform I/O itself.
///
/// Implement it over secure storage (keychain, keystore) to keep the session
/// across restarts. The manager reads lazily, on first use, and publishes
/// tokens only after [write] succeeded.
///
/// {@category storage}
abstract interface class TokenStore<T> {
  /// Returns the stored tokens, or `null` when there are none.
  Future<T?> read();

  /// Stores [tokens], replacing what was there.
  Future<void> write(T tokens);

  /// Removes the stored tokens.
  Future<void> delete();
}
