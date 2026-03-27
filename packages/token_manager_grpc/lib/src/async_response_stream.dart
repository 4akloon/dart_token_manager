import 'dart:async';
import 'package:async/async.dart';
import 'package:grpc/grpc.dart' as grpc;

/// Response stream that can swap the active gRPC stream during retry.
class AsyncResponseStream<R> extends StreamView<R>
    implements grpc.ResponseStream<R> {
  AsyncResponseStream._({
    required Stream<R> stream,
    required Future<Map<String, String>> headers,
    required Future<Map<String, String>> trailers,
    required Future<void> Function() cancel,
  }) : _headers = headers,
       _trailers = trailers,
       _cancelFn = cancel,
       super(stream);

  /// Creates a response stream from forwarding callback.
  factory AsyncResponseStream.fromCallback(
    Future<void> Function(
      StreamController<R> controller,
      void Function(grpc.ResponseStream<R>) setStream,
    )
    callback,
  ) {
    final headersCompleter = Completer<Map<String, String>>();
    final trailersCompleter = Completer<Map<String, String>>();
    grpc.ResponseStream<R>? currentStream;
    var isCancelled = false;

    // onCancel propagates subscriber cancellation to the active gRPC stream.
    // await for then throws GrpcError.cancelled() and the forward loop exits.
    late final StreamController<R> controller;
    controller = StreamController<R>(
      onCancel: () {
        isCancelled = true;
        currentStream?.cancel();
      },
    );

    Future<void> run() async {
      try {
        await callback(controller, (stream) {
          currentStream = stream;
          // Handle cancel that arrived while we were between streams (e.g. during
          // token refresh, when currentStream was temporarily null).
          if (isCancelled) {
            stream.cancel();
            return;
          }
          if (!headersCompleter.isCompleted) {
            stream.headers
                .then((h) {
                  if (!headersCompleter.isCompleted) {
                    headersCompleter.complete(h);
                  }
                })
                .catchError((Object _) {
                  // Swallow to allow the retry stream to provide headers instead
                });
          }
        });

        controller.close();

        if (!trailersCompleter.isCompleted) {
          final stream = currentStream;
          if (stream != null) {
            trailersCompleter.complete(stream.trailers);
          } else {
            trailersCompleter.complete(const <String, String>{});
          }
        }
        if (!headersCompleter.isCompleted) {
          headersCompleter.complete(const <String, String>{});
        }
      } catch (error) {
        controller.addError(error);
        controller.close();
        if (!headersCompleter.isCompleted) {
          headersCompleter.completeError(error);
        }
        if (!trailersCompleter.isCompleted) {
          trailersCompleter.completeError(error);
        }
      }
    }

    run();

    return AsyncResponseStream._(
      stream: controller.stream,
      headers: headersCompleter.future,
      trailers: trailersCompleter.future,
      cancel: () async {
        isCancelled = true;
        await currentStream?.cancel();
      },
    );
  }

  final Future<Map<String, String>> _headers;
  final Future<Map<String, String>> _trailers;
  final Future<void> Function() _cancelFn;

  @override
  grpc.ResponseFuture<R> get single =>
      _SyntheticResponseFuture(super.single, _headers, _trailers);

  @override
  Future<void> cancel() => _cancelFn();

  @override
  Future<Map<String, String>> get headers => _headers;

  @override
  Future<Map<String, String>> get trailers => _trailers;
}

/// A lightweight [grpc.ResponseFuture] that wraps an existing [Future] with
/// pre-resolved [headers] and [trailers]. Used by [AsyncResponseStream.single].
class _SyntheticResponseFuture<R> extends DelegatingFuture<R>
    implements grpc.ResponseFuture<R> {
  // ignore: use_super_parameters — DelegatingFuture uses a private param name
  _SyntheticResponseFuture(Future<R> future, this.headers, this.trailers)
    : super(future);

  @override
  final Future<Map<String, String>> headers;

  @override
  final Future<Map<String, String>> trailers;

  @override
  Future<void> cancel() async {}
}
