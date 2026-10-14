import 'dio_token_interceptor.dart';

/// The former name of [DioTokenInterceptor].
///
/// Kept as a subclass so 0.1 code compiles; switch to [DioTokenInterceptor].
///
/// {@category migration}
@Deprecated('Use DioTokenInterceptor.')
class RefreshInterceptor<T> extends DioTokenInterceptor<T> {
  /// Creates an interceptor over [manager]; see [DioTokenInterceptor.new].
  @Deprecated('Use DioTokenInterceptor.')
  RefreshInterceptor({
    required super.manager,
    required super.delegate,
    super.dio,
  });
}
