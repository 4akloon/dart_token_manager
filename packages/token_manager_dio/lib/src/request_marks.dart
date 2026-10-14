import 'package:dio/dio.dart';

/// Reads and writes what the interceptor keeps in [RequestOptions.extra].
final class RequestMarks<T> {
  /// Creates the helper.
  const RequestMarks();

  /// The `extra` key that holds the tokens a request was sent with.
  static const String tokensKey = 'token_manager_dio.tokens';

  /// The `extra` key that is `true` on the one replay of a request.
  static const String replayedKey = 'token_manager_dio.replayed';

  /// Returns the tokens [options] was sent with, or `null` when unknown.
  T? tokensOf(RequestOptions options) {
    return switch (options.extra[tokensKey]) {
      final T tokens => tokens,
      _ => null,
    };
  }

  /// Remembers that [options] is sent with [tokens].
  void recordTokens(RequestOptions options, T tokens) {
    options.extra[tokensKey] = tokens;
  }

  /// Whether [options] is the replay of an earlier request.
  bool isReplay(RequestOptions options) => options.extra[replayedKey] == true;

  /// Whether [options] can be sent a second time.
  ///
  /// A stream body is consumed by the first attempt.
  bool canReplay(RequestOptions options) => options.data is! Stream<Object?>;

  /// Returns the copy of [options] that is sent again with [tokens].
  ///
  /// The copy is marked as a replay, so it is never replayed itself. A
  /// [FormData] body is cloned because the first attempt finalized it.
  RequestOptions replayOf(RequestOptions options, T tokens) {
    return options.copyWith(
      data: switch (options.data) {
        FormData(:final clone) => clone(),
        final Object? data => data,
      },
      extra: {...options.extra, tokensKey: tokens, replayedKey: true},
    );
  }
}
