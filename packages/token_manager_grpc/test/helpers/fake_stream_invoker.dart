import 'package:grpc/grpc.dart' as grpc;

import 'fake_stream_call.dart';

/// A streaming invoker that records every call it makes.
final class FakeStreamInvoker<Q, R> {
  /// The calls made so far, in order.
  final List<FakeStreamCall<Q, R>> calls = [];

  /// The metadata that call number `n` reports, by `n`.
  final Map<int, Map<String, String>> metadataByCall = {};

  /// Makes a call; a tear-off matches `grpc.ClientStreamingInvoker`.
  grpc.ResponseStream<R> invoke(
    grpc.ClientMethod<Q, R> method,
    Stream<Q> requests,
    grpc.CallOptions options,
  ) {
    final call = FakeStreamCall<Q, R>(
      requests,
      options,
      metadata: metadataByCall[calls.length] ?? const {},
    );
    calls.add(call);
    return call;
  }

  /// Closes every call so that no test leaks a controller.
  Future<void> closeAll() async {
    for (final call in calls) {
      await call.responses.close();
    }
  }
}
