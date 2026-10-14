import 'package:grpc/grpc.dart' as grpc;

import 'fake_unary_call.dart';

/// A unary invoker that records every call it makes; each call stays
/// pending until the test answers it.
final class FakeUnaryInvoker<Q, R> {
  /// The calls made so far, in order.
  final List<FakeUnaryCall<R>> calls = [];

  /// The metadata that call number `n` reports, by `n`.
  final Map<int, Map<String, String>> metadataByCall = {};

  /// When set, every call fails its headers and trailers with it.
  Exception? metadataFailure;

  /// Makes a pending call; a tear-off matches `grpc.ClientUnaryInvoker`.
  grpc.ResponseFuture<R> invoke(
    grpc.ClientMethod<Q, R> method,
    Q request,
    grpc.CallOptions options,
  ) {
    final call = FakeUnaryCall<R>(
      options,
      metadata: metadataByCall[calls.length] ?? const {},
      metadataFailure: metadataFailure,
    );
    calls.add(call);
    return call;
  }
}
