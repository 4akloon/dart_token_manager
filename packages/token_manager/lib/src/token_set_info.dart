import 'token_info.dart';
import 'token_set.dart';

/// Reads the expiry of a [TokenSet].
final class TokenSetInfo implements TokenInfo<TokenSet> {
  /// Creates the info.
  const TokenSetInfo();

  @override
  DateTime? expiresAt(TokenSet tokens) => tokens.expiresAt;
}
