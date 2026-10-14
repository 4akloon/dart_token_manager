import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

/// Sends the access token as a bearer `Authorization` header.
final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  /// Creates the delegate.
  const BearerDelegate();

  @override
  void applyTo(RequestOptions options, TokenSet tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
  }
}
