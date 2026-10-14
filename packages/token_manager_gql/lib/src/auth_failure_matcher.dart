import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';

/// Decides whether a GraphQL failure means the server rejected the tokens.
///
/// A failure arrives on one of two channels: an error event, such as a
/// [ServerException] for an HTTP 401, or a [Response] whose `errors` carry an
/// auth code, such as `extensions.code: "UNAUTHENTICATED"` in an HTTP 200.
/// Extend this class to recognise other failures, for example the
/// `HttpLinkParserException` that `HttpLink` emits for a 401 whose body is not
/// GraphQL JSON.
class AuthFailureMatcher {
  /// Creates a matcher for the HTTP [statusCodes] of a [ServerException] and
  /// the [errorCodes] in `errors[].extensions.code` of a [Response].
  const AuthFailureMatcher({
    this.statusCodes = const {401},
    this.errorCodes = const {'UNAUTHENTICATED'},
  });

  /// The HTTP status codes that mean the tokens were rejected.
  final Set<int> statusCodes;

  /// The `extensions.code` values that mean the tokens were rejected.
  final Set<String> errorCodes;

  /// Whether the error event [error] means the tokens were rejected.
  bool isAuthError(Object error) =>
      error is ServerException && statusCodes.contains(error.statusCode);

  /// Whether one of the `errors` of [response] means the tokens were rejected.
  bool isAuthResponse(Response response) =>
      response.errors?.any(_isAuthGraphQLError) ?? false;

  bool _isAuthGraphQLError(GraphQLError error) {
    final code = error.extensions?['code'];
    return code is String && errorCodes.contains(code);
  }
}
