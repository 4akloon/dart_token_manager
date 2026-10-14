import 'package:grpc/grpc.dart' as grpc;

/// Attaches tokens to gRPC calls and recognises the errors that mean the
/// server rejected them.
///
/// The delegate keeps [GrpcTokenInterceptor] independent of the token scheme:
/// bearer metadata, API keys and custom headers are all just call options.
///
/// ```dart
/// final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
///   const BearerDelegate();
///
///   @override
///   grpc.CallOptions buildCallOptions(TokenSet? tokens) => grpc.CallOptions(
///     metadata: {
///       if (tokens != null) 'authorization': 'Bearer ${tokens.accessToken}',
///     },
///   );
/// }
/// ```
///
/// {@category getting-started}
abstract class RefreshInterceptorDelegate<T> {
  /// Creates a delegate.
  const RefreshInterceptorDelegate();

  /// Builds the call options, usually metadata, that carry [tokens].
  ///
  /// The interceptor always passes tokens; the parameter stays nullable for
  /// compatibility with 0.1.
  grpc.CallOptions? buildCallOptions(T? tokens);

  /// Returns `true` when [error] means the server rejected the tokens.
  ///
  /// The interceptor then refreshes the tokens and replays the call once.
  /// The default accepts `UNAUTHENTICATED`.
  bool shouldRefresh(grpc.GrpcError? error) {
    if (error?.code == grpc.StatusCode.unauthenticated) {
      return true;
    }

    return false;
  }
}
