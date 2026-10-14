import 'token_engine.dart';

/// Sends a call with valid tokens and replays it once after an auth failure.
final class AuthorizedCall<T> {
  /// Creates a call helper over [engine].
  AuthorizedCall(this._engine);

  final TokenEngine<T> _engine;

  /// Runs [send] with valid tokens.
  ///
  /// When [send] throws an exception for which [isAuthFailure] is true, the
  /// tokens it used are reported as rejected and [send] runs one more time
  /// with the replacement. A second failure, and any other failure, propagates.
  /// When no replacement exists the original failure is rethrown.
  Future<R> run<R>(
    Future<R> Function(T tokens) send, {
    required bool Function(Object error) isAuthFailure,
  }) async {
    final used = await _engine.validToken();
    try {
      return await send(used);
    } on Exception catch (error) {
      if (!isAuthFailure(error)) {
        rethrow;
      }
      final renewed = await _engine.validToken(rejected: used);
      if (identical(renewed, used)) {
        rethrow;
      }
      return send(renewed);
    }
  }
}
