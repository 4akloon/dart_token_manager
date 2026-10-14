import 'package:grpc/grpc.dart' as grpc;

/// Attaches tokens to gRPC calls and recognises the errors that mean the
/// server rejected them.
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
