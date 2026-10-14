import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;

import 'attempt_response_future.dart';
import 'call_attempts.dart';
import 'settling_stream.dart';

/// A [grpc.ResponseStream] whose headers, trailers and cancel follow the
/// call that answered, which may be a replay.
final class AttemptResponseStream<R> extends StreamView<R>
    implements grpc.ResponseStream<R> {
  /// Relays [responses], whose calls [attempts] records.
  AttemptResponseStream(Stream<R> responses, CallAttempts attempts)
    : _attempts = attempts,
      super(SettlingStream<R>(responses, attempts).stream);

  final CallAttempts _attempts;

  @override
  grpc.ResponseFuture<R> get single =>
      AttemptResponseFuture<R>(super.single, _attempts);

  @override
  Future<Map<String, String>> get headers => _attempts.headers;

  @override
  Future<Map<String, String>> get trailers => _attempts.trailers;

  @override
  Future<void> cancel() => _attempts.cancel();
}
