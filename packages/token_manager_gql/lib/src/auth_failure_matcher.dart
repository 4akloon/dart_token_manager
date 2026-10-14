import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';

/// Decides whether a GraphQL failure means the server rejected the tokens.
///
/// A failure arrives on one of two channels: an error event, such as a
/// [ServerException] for an HTTP 401, or a [Response] whose `errors` carry an
/// auth code, such as `extensions.code: "UNAUTHENTICATED"` in an HTTP 200. The
/// link replays a request only when this class says the tokens were rejected,
/// so a wrong rule either misses a rejection or replays a request that was
/// never about the tokens.
///
/// Extend this class to recognise other failures, for example the
/// `HttpLinkParserException` that `HttpLink` emits for a 401 whose body is not
/// GraphQL JSON:
///
/// ```dart
/// final class AppAuthFailureMatcher extends AuthFailureMatcher {
///   const AppAuthFailureMatcher();
///
///   @override
///   bool isAuthError(Object error) =>
///       (error is HttpLinkParserException &&
///           error.response.statusCode == 401) ||
///       super.isAuthError(error);
/// }
/// ```
///
/// {@category auth-failures}
class AuthFailureMatcher {
  /// Creates a matcher for the HTTP [statusCodes] of a [ServerException] and
  /// the [errorCodes] in `errors[].extensions.code` of a [Response].
  ///
  /// The defaults are replaced, not extended: with `statusCodes: {419}` a 401
  /// is no longer an auth failure.
  const AuthFailureMatcher({
    this.statusCodes = const {401},
    this.errorCodes = const {'UNAUTHENTICATED'},
  });

  /// The HTTP status codes that mean the tokens were rejected.
  final Set<int> statusCodes;

  /// The `extensions.code` values that mean the tokens were rejected.
  final Set<String> errorCodes;

  /// Whether the error event [error] means the tokens were rejected.
  ///
  /// By default this holds for a [ServerException] whose status code is in
  /// [statusCodes], and for one with status 403 whose parsed response carries
  /// an error code from [errorCodes]. A 403 without such a code is a missing
  /// permission and is not an auth failure.
  bool isAuthError(Object error) =>
      error is ServerException &&
      (statusCodes.contains(error.statusCode) || _isForbiddenRejection(error));

  bool _isForbiddenRejection(ServerException error) {
    final Response? parsed = error.parsedResponse;
    return error.statusCode == _forbidden &&
        parsed != null &&
        isAuthResponse(parsed);
  }

  static const int _forbidden = 403;

  /// Whether one of the `errors` of [response] means the tokens were rejected.
  ///
  /// By default this holds when an error has a string `extensions.code` that
  /// is in [errorCodes].
  bool isAuthResponse(Response response) =>
      response.errors?.any(_isAuthGraphQLError) ?? false;

  bool _isAuthGraphQLError(GraphQLError error) {
    final Object? code = error.extensions?['code'];
    return code is String && errorCodes.contains(code);
  }
}
