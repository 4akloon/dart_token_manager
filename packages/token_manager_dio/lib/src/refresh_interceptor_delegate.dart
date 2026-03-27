import 'package:dio/dio.dart';

/// Defines token application and refresh decision logic for Dio.
abstract class RefreshInterceptorDelegate<T> {
  /// Creates a delegate.
  const RefreshInterceptorDelegate();

  /// Applies authentication data from [tokens] to outgoing [options].
  void applyTokensToRequest(RequestOptions options, T? tokens);

  /// Returns `true` when the response indicates that token refresh is required.
  bool shouldRefresh(Response? response) {
    if (response?.statusCode == 401) {
      return true;
    }

    return false;
  }
}
