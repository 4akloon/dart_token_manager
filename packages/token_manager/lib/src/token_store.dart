/// Persists the tokens of one session; the core does no platform I/O itself.
abstract interface class TokenStore<T> {
  /// Returns the stored tokens, or `null` when there are none.
  Future<T?> read();

  /// Stores [tokens], replacing what was there.
  Future<void> write(T tokens);

  /// Removes the stored tokens.
  Future<void> delete();
}
