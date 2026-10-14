import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// Builds matchers for the [DioException] the interceptor throws.
final class DioErrors {
  /// Creates the matcher factory.
  const DioErrors();

  /// Matches a [DioException] whose `error` matches [error].
  ///
  /// When [status] is given, the exception must also carry a response with
  /// that status code.
  Matcher wrapping(Matcher error, {int? status}) {
    final matcher = isA<DioException>().having((e) => e.error, 'error', error);
    return status == null ? matcher : matcher.having(_status, 'status', status);
  }

  /// Matches a [DioException] whose response has the status code [status].
  Matcher withStatus(int status) {
    return isA<DioException>().having(_status, 'status', status);
  }

  int? _status(DioException error) => error.response?.statusCode;
}
