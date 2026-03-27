import 'dart:async';
import 'package:async/async.dart';
import 'package:grpc/grpc.dart' as grpc;

class AsyncResponseFuture<R> extends DelegatingFuture<R>
    implements grpc.ResponseFuture<R> {
  AsyncResponseFuture._(this._result) : super(_result.future);
  AsyncResponseFuture() : this._(Completer<R>());

  factory AsyncResponseFuture.fromCallback(
    Future<grpc.ResponseFuture<R>> Function(
      void Function(grpc.Response) setResponse,
    )
    callback,
  ) {
    final asyncResponse = AsyncResponseFuture<R>();
    callback(
      (response) => asyncResponse.pendingCall = response,
    ).then(asyncResponse.complete).catchError(asyncResponse.completeError);

    return asyncResponse;
  }

  grpc.Response? pendingCall;

  final Completer<R> _result;
  final _headers = Completer<Map<String, String>>();
  final _trailers = Completer<Map<String, String>>();

  void complete(grpc.ResponseFuture<R> other) {
    _result.complete(other);
    _headers.complete(other.headers);
    _trailers.complete(other.trailers);
  }

  void completeError(Object error) {
    _result.completeError(error);
    _headers.completeError(error);
    _trailers.completeError(error);
  }

  @override
  Future<void> cancel() async {
    await pendingCall?.cancel();
  }

  @override
  Future<Map<String, String>> get headers => _headers.future;

  @override
  Future<Map<String, String>> get trailers => _trailers.future;
}
