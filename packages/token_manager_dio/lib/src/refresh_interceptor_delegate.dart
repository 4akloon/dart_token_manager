import 'package:dio/dio.dart';

abstract class RefreshInterceptorDelegate<T> {
  const RefreshInterceptorDelegate();

  void applyTokensToRequest(RequestOptions options, T? tokens);

  bool shouldRefresh(Response? response) {
    if (response?.statusCode == 401) {
      return true;
    }

    return false;
  }
}
