import 'package:test/test.dart';
import 'package:token_manager/src/token_set.dart';
import 'package:token_manager/src/token_set_info.dart';

void main() {
  test('token sets with the same fields are equal', () {
    final expiresAt = DateTime.utc(2026);

    expect(
      TokenSet(accessToken: 'a', refreshToken: 'r', expiresAt: expiresAt),
      TokenSet(accessToken: 'a', refreshToken: 'r', expiresAt: expiresAt),
    );
  });

  test('token sets with different access tokens are not equal', () {
    expect(
      const TokenSet(accessToken: 'a'),
      isNot(const TokenSet(accessToken: 'b')),
    );
  });

  test('TokenSetInfo reads the expiry from the token set', () {
    final expiresAt = DateTime.utc(2026);

    expect(
      const TokenSetInfo().expiresAt(
        TokenSet(accessToken: 'a', expiresAt: expiresAt),
      ),
      expiresAt,
    );
  });

  test('TokenSetInfo returns null when the token set never expires', () {
    expect(
      const TokenSetInfo().expiresAt(const TokenSet(accessToken: 'a')),
      isNull,
    );
  });
}
