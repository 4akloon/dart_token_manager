import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;

/// Tracks the gRPC calls made for one intercepted call and exposes the
/// headers, trailers and cancel of the call that answered.
///
/// A replay makes a new call. The headers and trailers follow the latest call
/// once [settle] runs, that is when no further replay can happen.
final class CallAttempts {
  /// Creates a tracker that has made no call yet.
  CallAttempts() {
    // An error stays visible to whoever awaits these futures, but one that
    // nobody awaits must not escape as an uncaught zone error.
    _headers.future.ignore();
    _trailers.future.ignore();
  }

  /// The metadata reported when no call was ever made.
  static const Map<String, String> _noMetadata = {};

  /// The message of the error that a call started after [cancel] fails with.
  static const String _cancelledMessage = 'Cancelled by client.';

  final Completer<Map<String, String>> _headers =
      Completer<Map<String, String>>();
  final Completer<Map<String, String>> _trailers =
      Completer<Map<String, String>>();
  _Call? _latest;
  bool _cancelled = false;
  bool _settled = false;

  /// The headers of the call that answered.
  Future<Map<String, String>> get headers => _headers.future;

  /// The trailers of the call that answered.
  Future<Map<String, String>> get trailers => _trailers.future;

  /// Makes a unary call with [call] and records it as the latest call.
  ///
  /// Throws a cancelled `GrpcError` without calling [call] after [cancel].
  grpc.ResponseFuture<R> unary<R>(grpc.ResponseFuture<R> Function() call) {
    _ensureNotCancelled();
    final made = call();
    _latest = (
      headers: () => made.headers,
      trailers: () => made.trailers,
      cancel: made.cancel,
    );
    return made;
  }

  /// Makes a streaming call with [call] and records it as the latest call.
  ///
  /// Throws a cancelled `GrpcError` without calling [call] after [cancel].
  grpc.ResponseStream<R> streaming<R>(grpc.ResponseStream<R> Function() call) {
    _ensureNotCancelled();
    final made = call();
    _latest = (
      headers: () => made.headers,
      trailers: () => made.trailers,
      cancel: made.cancel,
    );
    return made;
  }

  /// Fixes the latest call as the one whose headers and trailers are
  /// reported; later calls do nothing.
  void settle() {
    if (_settled) {
      return;
    }
    _settled = true;
    final latest = _latest;
    if (latest == null) {
      _headers.complete(_noMetadata);
      _trailers.complete(_noMetadata);
      return;
    }
    _follow(latest.headers(), _headers);
    _follow(latest.trailers(), _trailers);
  }

  /// Settles once [response] completes, with a value or an error.
  void settleWhenDone(Future<Object?> response) {
    unawaited(response.then<void>(_settleOnValue, onError: _settleOnError));
  }

  /// Cancels the latest call and makes every later call fail as cancelled.
  Future<void> cancel() async {
    _cancelled = true;
    settle();
    await _latest?.cancel();
  }

  void _ensureNotCancelled() {
    if (_cancelled) {
      throw const grpc.GrpcError.cancelled(_cancelledMessage);
    }
  }

  void _settleOnValue(Object? _) => settle();

  void _settleOnError(Object _) => settle();

  void _follow(
    Future<Map<String, String>> source,
    Completer<Map<String, String>> target,
  ) {
    unawaited(
      source.then<void>(target.complete, onError: target.completeError),
    );
  }
}

/// What [CallAttempts] keeps of one call.
///
/// The metadata is read only once the call is known to be the one that
/// answered, so a replaced call's metadata is never listened to.
typedef _Call = ({
  Future<Map<String, String>> Function() headers,
  Future<Map<String, String>> Function() trailers,
  Future<void> Function() cancel,
});
