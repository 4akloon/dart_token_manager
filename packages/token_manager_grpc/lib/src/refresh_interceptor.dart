import 'grpc_token_interceptor.dart';

/// The former name of [GrpcTokenInterceptor].
@Deprecated('Use GrpcTokenInterceptor.')
class RefreshInterceptor<T> extends GrpcTokenInterceptor<T> {
  /// Creates an interceptor; see [GrpcTokenInterceptor.new].
  @Deprecated('Use GrpcTokenInterceptor.')
  const RefreshInterceptor({required super.manager, required super.delegate});
}
