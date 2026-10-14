import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;

/// A streaming call whose responses the test pushes, like a call from a
/// channel: it listens to its request stream at once and records it.
final class FakeStreamCall<Q, R> extends StreamView<R>
    implements grpc.ResponseStream<R> {
  /// Creates a call made with [requests] and [options] that reports
  /// [metadata] as its headers and trailers.
  FakeStreamCall(
    Stream<Q> requests,
    grpc.CallOptions options, {
    Map<String, String> metadata = const {},
  }) : this._(StreamController<R>(), requests, options, metadata);

  FakeStreamCall._(
    this.responses,
    Stream<Q> requests,
    this.options,
    this._metadata,
  ) : super(responses.stream) {
    responses.onCancel = _onCancel;
    _requests = requests.listen(sent.add);
  }

  final Map<String, String> _metadata;
  StreamSubscription<Q>? _requests;

  /// The controller the test pushes responses into.
  final StreamController<R> responses;

  /// The options the call was made with.
  final grpc.CallOptions options;

  /// The requests the call has read so far.
  final List<Q> sent = [];

  /// Whether the call was cancelled, by [cancel] or by its listener.
  bool cancelled = false;

  /// The `authorization` metadata the call was made with.
  String? get authorization => options.metadata['authorization'];

  @override
  grpc.ResponseFuture<R> get single => throw UnsupportedError('not faked');

  @override
  Future<Map<String, String>> get headers async => _metadata;

  @override
  Future<Map<String, String>> get trailers async => _metadata;

  @override
  Future<void> cancel() async {
    await _onCancel();
    if (!responses.isClosed) {
      responses.addError(const grpc.GrpcError.cancelled());
      await responses.close();
    }
  }

  Future<void> _onCancel() async {
    cancelled = true;
    await _requests?.cancel();
  }
}
