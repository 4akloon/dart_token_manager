import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:test/test.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

/// Also treats a body that is not GraphQL JSON as a rejection, as an app
/// whose server answers 401 with an HTML page would.
final class _ParserAwareMatcher extends AuthFailureMatcher {
  const _ParserAwareMatcher();

  @override
  bool isAuthError(Object error) =>
      error is ResponseFormatException || super.isAuthError(error);
}

void main() {
  const matcher = AuthFailureMatcher();

  Response responseWithCode(Object? code) => Response(
    errors: [
      GraphQLError(message: 'failed', extensions: {'code': code}),
    ],
    response: const {},
  );

  test('a ServerException with status 401 is an auth error', () {
    expect(matcher.isAuthError(const ServerException(statusCode: 401)), isTrue);
  });

  test('a ServerException with another status is not an auth error', () {
    expect(
      matcher.isAuthError(const ServerException(statusCode: 500)),
      isFalse,
    );
  });

  test('a ServerException without a status is not an auth error', () {
    expect(matcher.isAuthError(const ServerException()), isFalse);
  });

  test('an exception that is not a ServerException is not an auth error', () {
    expect(matcher.isAuthError(const FormatException('401')), isFalse);
  });

  test('a response with the UNAUTHENTICATED code is an auth response', () {
    expect(matcher.isAuthResponse(responseWithCode('UNAUTHENTICATED')), isTrue);
  });

  test('a response with another code is not an auth response', () {
    expect(matcher.isAuthResponse(responseWithCode('FORBIDDEN')), isFalse);
  });

  test('a response whose code is not a string is not an auth response', () {
    expect(matcher.isAuthResponse(responseWithCode(401)), isFalse);
  });

  test('a response without errors is not an auth response', () {
    const response = Response(data: {'me': 'ada'}, response: {});
    expect(matcher.isAuthResponse(response), isFalse);
  });

  test('a response whose error has no extensions is not an auth response', () {
    const response = Response(
      errors: [GraphQLError(message: 'failed')],
      response: {},
    );
    expect(matcher.isAuthResponse(response), isFalse);
  });

  group('with custom codes', () {
    const custom = AuthFailureMatcher(
      statusCodes: {419},
      errorCodes: {'invalid-jwt'},
    );

    test('a custom status code is an auth error', () {
      expect(
        custom.isAuthError(const ServerException(statusCode: 419)),
        isTrue,
      );
    });

    test('the default status code is no longer an auth error', () {
      expect(
        custom.isAuthError(const ServerException(statusCode: 401)),
        isFalse,
      );
    });

    test('a custom error code is an auth response', () {
      expect(custom.isAuthResponse(responseWithCode('invalid-jwt')), isTrue);
    });
  });

  test('a ResponseFormatException is not an auth error by default', () {
    expect(matcher.isAuthError(const ResponseFormatException()), isFalse);
  });

  test('a subclass can recognise more errors', () {
    const parserAware = _ParserAwareMatcher();
    expect(parserAware.isAuthError(const ResponseFormatException()), isTrue);
  });

  test('a subclass keeps the default status check', () {
    const parserAware = _ParserAwareMatcher();
    expect(
      parserAware.isAuthError(const ServerException(statusCode: 401)),
      isTrue,
    );
  });
}
