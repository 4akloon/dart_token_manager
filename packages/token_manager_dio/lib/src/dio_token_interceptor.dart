import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';

import 'refresh_interceptor_delegate.dart';
import 'request_marks.dart';

/// Dio interceptor that attaches tokens and replays a request once after an
/// auth failure.
///
/// The interceptor never refreshes by itself: it asks [TokenManager] for a
/// valid token before sending and, when the server rejects the request, for a
/// replacement of the rejected one. This keeps the refresh single-flight and
/// leaves storage and logout to the core. A replay is marked, so it cannot
/// loop.
///
/// A failure to obtain or renew tokens reaches the caller as a [DioException]
/// whose `error` is a `NotAuthenticated`, `InvalidGrant` or `Transient`.
///
/// ```dart
/// dio.interceptors.add(
///   DioTokenInterceptor<TokenSet>(
///     manager: manager,
///     delegate: const BearerDelegate(),
///     dio: dio,
///   ),
/// );
/// ```
///
/// {@category getting-started}
class DioTokenInterceptor<T> extends Interceptor {
  /// Creates an interceptor over [manager].
  ///
  /// A request that [delegate] reports as an auth failure is sent again once
  /// through [dio] with the tokens [manager] returns. Pass the [Dio] the
  /// interceptor is added to, so the replay keeps its adapter, its other
  /// interceptors and its timeouts; the replay is marked and never loops.
  /// Without [dio] a plain `Dio` sends the replay.
  DioTokenInterceptor({
    required TokenManager<T> manager,
    required RefreshInterceptorDelegate<T> delegate,
    Dio? dio,
  }) : _manager = manager,
       _delegate = delegate,
       _dio = dio ?? Dio();

  final TokenManager<T> _manager;
  final RefreshInterceptorDelegate<T> _delegate;
  final Dio _dio;
  final RequestMarks<T> _marks = RequestMarks<T>();

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_marks.isReplay(options)) {
      handler.next(options);
      return;
    }
    try {
      final tokens = await _manager.validToken();
      _delegate.applyTo(options, tokens);
      _marks.recordTokens(options, tokens);
      handler.next(options);
    } on Exception catch (error, stackTrace) {
      handler.reject(_failure(options, error, stackTrace), true);
    }
  }

  @override
  Future<void> onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) async {
    if (!_delegate.shouldRefresh(response)) {
      handler.next(response);
      return;
    }
    try {
      final replayed = await _replay(response.requestOptions, response);
      if (replayed == null) {
        handler.next(response);
      } else {
        handler.resolve(replayed);
      }
    } on DioException catch (error) {
      handler.reject(error, true);
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (_isOwnFailure(err) || !_delegate.shouldRefresh(err.response)) {
      handler.next(err);
      return;
    }
    try {
      final replayed = await _replay(err.requestOptions, err.response);
      if (replayed == null) {
        handler.next(err);
      } else {
        handler.resolve(replayed);
      }
    } on DioException catch (error) {
      handler.next(error);
    }
  }

  /// Whether this interceptor produced [err] itself, so it must not be retried.
  bool _isOwnFailure(DioException err) {
    return err.error is RefreshFailure || err.error is NotAuthenticated;
  }

  /// Sends [options] again with new tokens; `null` means the failure passes on.
  ///
  /// Throws a [DioException] when the tokens cannot be renewed or the replay
  /// fails.
  Future<Response<Object?>?> _replay(
    RequestOptions options,
    Response<Object?>? rejected,
  ) async {
    final used = _marks.tokensOf(options);
    if (used == null ||
        _marks.isReplay(options) ||
        !_marks.canReplay(options)) {
      return null;
    }
    try {
      final renewed = await _manager.validToken(rejected: used);
      if (identical(renewed, used)) {
        return null;
      }
      return await _send(_marks.replayOf(options, renewed), renewed);
    } on DioException {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _failure(options, error, stackTrace, response: rejected);
    }
  }

  Future<Response<Object?>> _send(RequestOptions options, T tokens) async {
    _delegate.applyTo(options, tokens);
    // No type argument on purpose: `fetch<Object?>` would reset the response
    // type of the request to JSON, `fetch` infers `dynamic` and leaves it.
    final response = await _dio.fetch(options);
    return response;
  }

  DioException _failure(
    RequestOptions options,
    Object error,
    StackTrace stackTrace, {
    Response<Object?>? response,
  }) {
    return DioException(
      requestOptions: options,
      response: response,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
