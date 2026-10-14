import 'package:async/async.dart';
import 'package:grpc/grpc.dart' as grpc;

import 'call_attempts.dart';

/// A [grpc.ResponseFuture] whose headers, trailers and cancel follow the
/// call that answered, which may be a replay.
final class AttemptResponseFuture<R> extends DelegatingFuture<R>
    implements grpc.ResponseFuture<R> {
  /// Wraps [response] and settles [attempts] once it completes.
  AttemptResponseFuture(Future<R> response, CallAttempts attempts)
    : _attempts = attempts,
      super(response) {
    attempts.settleWhenDone(response);
  }

  final CallAttempts _attempts;

  @override
  Future<Map<String, String>> get headers => _attempts.headers;

  @override
  Future<Map<String, String>> get trailers => _attempts.trailers;

  @override
  Future<void> cancel() => _attempts.cancel();
}
