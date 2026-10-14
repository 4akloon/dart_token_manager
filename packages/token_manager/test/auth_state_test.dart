import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';

void main() {
  test('tokensOrNull is null when unauthenticated', () {
    expect(const Unauthenticated<String>().tokensOrNull, isNull);
  });

  test('tokensOrNull returns the tokens when authenticated', () {
    expect(const Authenticated<String>('a').tokensOrNull, 'a');
  });

  test('tokensOrNull returns the tokens while refreshing', () {
    expect(const Refreshing<String>('a').tokensOrNull, 'a');
  });
}
