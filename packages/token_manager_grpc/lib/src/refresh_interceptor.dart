import 'grpc_token_interceptor.dart';

/// The former name of [GrpcTokenInterceptor].
///
/// It stays as a subclass so 0.1 code keeps compiling; see the migration
/// guide for the behaviour changes.
///
/// {@category migration}
@Deprecated('Use GrpcTokenInterceptor.')
class RefreshInterceptor<T> extends GrpcTokenInterceptor<T> {
  /// Creates an interceptor; see [GrpcTokenInterceptor.new].
  @Deprecated('Use GrpcTokenInterceptor.')
  const RefreshInterceptor({required super.manager, required super.delegate});
}
