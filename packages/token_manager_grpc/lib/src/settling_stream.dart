import 'dart:async';

import 'call_attempts.dart';

/// Relays a stream and settles [CallAttempts] when the stream first delivers
/// something (an event, an error or its end) or is cancelled.
///
/// The source is subscribed with `listen`, so pause, resume and cancel reach
/// it.
final class SettlingStream<R> {
  /// Creates a relay of [source]; nothing happens until [stream] is listened
  /// to.
  SettlingStream(Stream<R> source, CallAttempts attempts)
    : _source = source,
      _attempts = attempts {
    _controller = StreamController<R>(
      onListen: _listen,
      onPause: _pause,
      onResume: _resume,
      onCancel: _cancel,
    );
  }

  final Stream<R> _source;
  final CallAttempts _attempts;

  // Assigned once in the constructor body: its callbacks need `this`.
  late final StreamController<R> _controller;

  StreamSubscription<R>? _subscription;

  /// The relayed stream; it supports a single subscription.
  Stream<R> get stream => _controller.stream;

  void _listen() {
    _subscription = _source.listen(_onData, onError: _onError, onDone: _onDone);
  }

  void _onData(R event) {
    _attempts.settle();
    _controller.add(event);
  }

  void _onError(Object error, StackTrace stackTrace) {
    _attempts.settle();
    _controller.addError(error, stackTrace);
  }

  void _onDone() {
    _attempts.settle();
    unawaited(_controller.close());
  }

  void _pause() => _subscription?.pause();

  void _resume() => _subscription?.resume();

  Future<void> _cancel() {
    _attempts.settle();
    final subscription = _subscription;
    _subscription = null;
    return subscription?.cancel() ?? Future<void>.value();
  }
}
