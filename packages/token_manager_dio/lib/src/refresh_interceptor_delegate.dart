import 'package:dio/dio.dart';

/// Defines token application and refresh decision logic for Dio.
///
/// Override [applyTo]. A 0.1 delegate that overrides only
/// `applyTokensToRequest` keeps working: the default [applyTo] calls it.
abstract class RefreshInterceptorDelegate<T> {
  /// Creates a delegate.
  const RefreshInterceptorDelegate();

  /// Applies authentication data from [tokens] to outgoing [options].
  ///
  /// [tokens] is never `null`: a request without tokens fails with
  /// `NotAuthenticated` before it is sent. The default calls the deprecated
  /// `applyTokensToRequest`, so delegates written for 0.1 keep working.
  void applyTo(RequestOptions options, T tokens) {
    // ignore: deprecated_member_use_from_same_package, the bridge to 0.1 delegates.
    applyTokensToRequest(options, tokens);
  }

  /// The former name of [applyTo].
  ///
  /// The default throws a [StateError]: a delegate has to override [applyTo]
  /// or this method. Only [applyTo] calls this method, so a delegate that
  /// overrides neither fails loudly instead of recursing.
  @Deprecated('Override applyTo.')
  void applyTokensToRequest(RequestOptions options, T? tokens) {
    throw StateError(
      '$runtimeType must override RefreshInterceptorDelegate.applyTo.',
    );
  }

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
