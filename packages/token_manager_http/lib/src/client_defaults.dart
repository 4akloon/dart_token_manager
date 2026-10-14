import 'package:http/http.dart';
import 'package:token_manager/token_manager.dart';

/// The behaviour `HttpTokenClient` falls back to for each option left unset.
///
/// Internal: not exported from the package barrel.
final class ClientDefaults {
  const ClientDefaults._();

  /// The status that rejects the tokens unless `isAuthFailure` says
  /// otherwise.
  static const int unauthorized = 401;

  /// Builds an `Authorization: Bearer` header from a [TokenSet].
  ///
  /// Throws a [StateError] for any other token type.
  static Map<String, String> bearer(Object? tokens) => switch (tokens) {
    TokenSet(:final accessToken) => {'Authorization': 'Bearer $accessToken'},
    _ => throw StateError('HttpTokenClient needs headers for this token type.'),
  };

  /// Whether [response] has the [unauthorized] status.
  static bool isUnauthorized(BaseResponse response) =>
      response.statusCode == unauthorized;

  /// Authorizes every request.
  static bool authorizesAll(BaseRequest request) => true;

  /// Throws an [ArgumentError] when [headers] is missing and the token type
  /// [T] is not [TokenSet].
  static void requireHeaders<T>(Object? headers) {
    if (headers == null && T != TokenSet) {
      throw ArgumentError.value(
        headers,
        'headers',
        'is required unless the token type is TokenSet',
      );
    }
  }
}
