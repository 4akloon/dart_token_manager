/// A ready-made token value for apps that need no custom token type.
///
/// Pair it with [TokenSetInfo] so the manager knows when it expires.
///
/// ```dart
/// final tokens = TokenSet(
///   accessToken: 'access',
///   refreshToken: 'refresh',
///   expiresAt: DateTime.now().add(const Duration(hours: 1)),
/// );
/// ```
///
/// {@category getting-started}
final class TokenSet {
  /// Creates a token set.
  const TokenSet({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  /// The access token.
  final String accessToken;

  /// The refresh token, if the server issued one.
  final String? refreshToken;

  /// When the access token expires, or `null` if it never does.
  final DateTime? expiresAt;

  @override
  bool operator ==(Object other) =>
      other is TokenSet &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, expiresAt);
}
