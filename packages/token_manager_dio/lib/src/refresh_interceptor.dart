import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'refresh_interceptor_delegate.dart';

class RefreshInterceptor<T> extends Interceptor {
  RefreshInterceptor({
    required TokenManager<T> manager,
    Dio? dio,
    required RefreshInterceptorDelegate<T> delegate,
  }) : _manager = manager,
       _dio = dio ?? Dio(),
       _delegate = delegate;

  final TokenManager<T> _manager;
  final Dio _dio;
  final RefreshInterceptorDelegate<T> _delegate;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    await _manager.waitForFresh;

    final tokens = _manager.tokens;

    _delegate.applyTokensToRequest(options, tokens);

    options.extra['_auth_tokens'] = tokens;

    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    if (_delegate.shouldRefresh(response)) {
      final requestTokens = response.requestOptions.extra['_auth_tokens'];

      final tokens = _manager.tokens;

      if (tokens == null) {
        handler.reject(DioException(requestOptions: response.requestOptions));
        return;
      }

      if (requestTokens == tokens) {
        await _manager.executeRefresh();
      }

      try {
        final newResponse = await _makeNewRequest(
          response.requestOptions,
          _manager.tokens,
        );

        handler.resolve(newResponse);
      } on DioException catch (e) {
        handler.reject(e);
      }
    } else {
      handler.next(response);
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (_delegate.shouldRefresh(err.response)) {
      final requestTokens = err.requestOptions.extra['_auth_tokens'];

      final tokens = _manager.tokens;

      if (tokens == null) {
        handler.next(err);
        return;
      }

      if (requestTokens == tokens) {
        await _manager.executeRefresh();
      }

      final newTokens = _manager.tokens;

      if (newTokens == null) {
        handler.next(err);
        return;
      }

      try {
        final response = await _makeNewRequest(err.requestOptions, newTokens);

        handler.resolve(response);
      } on DioException catch (e) {
        handler.next(e);
      }
    } else {
      handler.next(err);
    }
  }

  Future<Response<dynamic>> _makeNewRequest(
    RequestOptions options,
    T? tokens,
  ) async {
    _dio.options.baseUrl = options.baseUrl;

    _delegate.applyTokensToRequest(options, tokens);

    return _dio.request(
      options.path,
      cancelToken: options.cancelToken,
      data: switch (options.data) {
        FormData(:final clone) => clone(),
        final data => data,
      },
      onReceiveProgress: options.onReceiveProgress,
      onSendProgress: options.onSendProgress,
      queryParameters: options.queryParameters,
      options: Options(
        method: options.method,
        sendTimeout: options.sendTimeout,
        receiveTimeout: options.receiveTimeout,
        extra: options.extra,
        headers: options.headers,
        responseType: options.responseType,
        contentType: options.contentType,
        validateStatus: options.validateStatus,
        receiveDataWhenStatusError: options.receiveDataWhenStatusError,
        followRedirects: options.followRedirects,
        maxRedirects: options.maxRedirects,
        requestEncoder: options.requestEncoder,
        responseDecoder: options.responseDecoder,
        listFormat: options.listFormat,
      ),
    );
  }
}
