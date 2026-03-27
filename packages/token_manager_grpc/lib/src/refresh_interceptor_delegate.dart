import 'package:grpc/grpc.dart' as grpc;

abstract class RefreshInterceptorDelegate<T> {
  const RefreshInterceptorDelegate();

  grpc.CallOptions? buildCallOptions(T? tokens);

  bool shouldRefresh(grpc.GrpcError? error) {
    if (error?.code == grpc.StatusCode.unauthenticated) {
      return true;
    }

    return false;
  }
}
