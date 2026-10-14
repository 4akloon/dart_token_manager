/// Where a session stands; observed through `TokenManager.states`.
///
/// The hierarchy is sealed, so a `switch` over it is exhaustive:
///
/// ```dart
/// final label = switch (state) {
///   Unauthenticated() => 'signed out',
///   Authenticated(:final tokens) => 'signed in',
///   Refreshing(:final tokens) => 'refreshing',
/// };
/// ```
///
/// {@category concepts}
sealed class AuthState<T> {
  /// Creates a state.
  const AuthState();

  /// Returns the tokens of this state, or `null` when there are none.
  T? get tokensOrNull => switch (this) {
    Unauthenticated() => null,
    Authenticated(:final tokens) => tokens,
    Refreshing(:final tokens) => tokens,
  };
}

/// There are no tokens: the user is signed out.
///
/// {@category concepts}
final class Unauthenticated<T> extends AuthState<T> {
  /// Creates the state.
  const Unauthenticated();
}

/// The user is signed in with [tokens].
///
/// {@category concepts}
final class Authenticated<T> extends AuthState<T> {
  /// Creates the state.
  const Authenticated(this.tokens);

  /// The current tokens.
  final T tokens;
}

/// A refresh is running; [tokens] are the ones being replaced.
///
/// The state returns to [Authenticated] when the refresh succeeds or fails
/// transiently, and to [Unauthenticated] when the grant is dead.
///
/// {@category concepts}
final class Refreshing<T> extends AuthState<T> {
  /// Creates the state.
  const Refreshing(this.tokens);

  /// The tokens being replaced.
  final T tokens;
}
