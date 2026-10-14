import 'package:dio/dio.dart';

/// Defines token application and refresh decision logic for Dio.
abstract class RefreshInterceptorDelegate<T> {
  /// Creates a delegate.
  const RefreshInterceptorDelegate();

  /// Applies authentication data from [tokens] to outgoing [options].
  ///
  /// Since 0.2 [tokens] is never `null`: a request without tokens fails with
  /// `NotAuthenticated` before it is sent. The parameter stays nullable so
  /// that 0.1 delegates keep compiling.
  void applyTokensToRequest(RequestOptions options, T? tokens);

  /// Returns `true` when [response] is an auth failure the request is
  /// replayed for.
  ///
  /// The default treats status 401 as an auth failure. [response] is `null`
  /// when the request failed without an answer, which is never one.
  bool shouldRefresh(Response? response) {
    if (response?.statusCode == 401) {
      return true;
    }

    return false;
  }
}
