import 'dart:async';

/// Watches the request stream of a streaming call and tells whether the call
/// can be made again without listening to that stream a second time.
///
/// Only a stream that ended after at most one request, the shape of a
/// server-streaming call, can be made again: its request is sent again from
/// memory. A call whose stream sent more requests, or had not ended, is never
/// made again, whatever its method type.
final class RequestLog<Q> {
  /// Creates a log of [requests].
  RequestLog(this._requests);

  /// The most requests a call that can be made again may have sent.
  static const int _replayableRequests = 1;

  final Stream<Q> _requests;
  final List<Q> _sent = [];
  int _count = 0;
  bool _ended = false;
  bool _opened = false;

  /// Whether the requests ended after at most one request.
  bool get isReplayable => _ended && _count <= _replayableRequests;

  /// The request stream for the next call: the original one, watched, the
  /// first time, and the recorded request after that.
  Stream<Q> next() {
    if (_opened) {
      return Stream<Q>.fromIterable(List<Q>.of(_sent));
    }
    _opened = true;
    return _requests.transform(
      StreamTransformer<Q, Q>.fromHandlers(
        handleData: _record,
        handleDone: _end,
      ),
    );
  }

  void _record(Q request, EventSink<Q> sink) {
    _count++;
    if (_count <= _replayableRequests) {
      _sent.add(request);
    }
    sink.add(request);
  }

  void _end(EventSink<Q> sink) {
    _ended = true;
    sink.close();
  }
}
