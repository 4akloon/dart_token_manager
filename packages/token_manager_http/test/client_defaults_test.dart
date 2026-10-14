import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/src/client_defaults.dart';

void main() {
  group('ClientDefaults', () {
    test('bearer builds an Authorization header for a TokenSet', () {
      final headers = ClientDefaults.bearer(
        const TokenSet(accessToken: 'abc'),
      );

      expect(headers, {'Authorization': 'Bearer abc'});
    });

    test('bearer throws a StateError for another token type', () {
      expect(
        () => ClientDefaults.bearer('plain'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'HttpTokenClient needs headers for this token type.',
          ),
        ),
      );
    });

    test('only status 401 is unauthorized', () {
      expect(ClientDefaults.isUnauthorized(Response('', 401)), isTrue);
      expect(ClientDefaults.isUnauthorized(Response('', 403)), isFalse);
      expect(ClientDefaults.isUnauthorized(Response('', 200)), isFalse);
    });

    test('authorizesAll authorizes every request', () {
      final request = Request('GET', Uri.parse('https://example.com/login'));

      expect(ClientDefaults.authorizesAll(request), isTrue);
    });

    test('requireHeaders throws an ArgumentError without headers', () {
      expect(
        () => ClientDefaults.requireHeaders<String>(null),
        throwsArgumentError,
      );
    });

    test('requireHeaders accepts a missing builder for a TokenSet', () {
      expect(
        () => ClientDefaults.requireHeaders<TokenSet>(null),
        returnsNormally,
      );
    });

    test('requireHeaders accepts a builder for any type', () {
      expect(
        () => ClientDefaults.requireHeaders<String>(Object()),
        returnsNormally,
      );
    });
  });
}
