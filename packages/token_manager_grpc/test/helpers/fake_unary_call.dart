import 'dart:async';

import 'package:async/async.dart';
import 'package:grpc/grpc.dart' as grpc;

/// A unary call whose outcome the test decides, like a call from a channel.
final class FakeUnaryCall<R> extends DelegatingFuture<R>
    implements grpc.ResponseFuture<R> {
  /// Creates a pending call made with [options] that reports [metadata] as
  /// its headers and trailers, or fails them with [metadataFailure].
  FakeUnaryCall(
    grpc.CallOptions options, {
    Map<String, String> metadata = const {},
    Exception? metadataFailure,
  }) : this._(Completer<R>(), options, metadata, metadataFailure);

  FakeUnaryCall._(
    this._result,
    this.options,
    this._metadata,
    this._metadataFailure,
  ) : super(_result.future);

  final Completer<R> _result;
  final Map<String, String> _metadata;
  final Exception? _metadataFailure;

  /// The options the call was made with.
  final grpc.CallOptions options;

  /// Whether [cancel] was called.
  bool cancelled = false;

  /// The `authorization` metadata the call was made with.
  String? get authorization => options.metadata['authorization'];

  /// Answers the call with [response].
  void succeed(R response) => _result.complete(response);

  /// Fails the call with [error].
  void fail(Object error) => _result.completeError(error);

  @override
  Future<Map<String, String>> get headers => _reportMetadata();

  @override
  Future<Map<String, String>> get trailers => _reportMetadata();

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_result.isCompleted) {
      _result.completeError(const grpc.GrpcError.cancelled());
    }
  }

  Future<Map<String, String>> _reportMetadata() async {
    final failure = _metadataFailure;
    if (failure != null) {
      throw failure;
    }
    return _metadata;
  }
}
