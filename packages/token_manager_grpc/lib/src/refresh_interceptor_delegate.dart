import 'package:grpc/grpc.dart' as grpc;

/// Defines token application and refresh decision logic for gRPC calls.
abstract class RefreshInterceptorDelegate<T> {
  /// Creates a delegate.
  const RefreshInterceptorDelegate();

  /// Builds auth call options using currently available [tokens].
  grpc.CallOptions? buildCallOptions(T? tokens);

  /// Returns `true` when [error] means auth should be refreshed.
  bool shouldRefresh(grpc.GrpcError? error) {
    if (error?.code == grpc.StatusCode.unauthenticated) {
      return true;
    }

    return false;
  }
}
