import 'dart:async';

/// Relays a stream that needs valid tokens to open.
///
/// The source is subscribed with `listen`, never `await for`, so pause, resume
/// and cancel reach it. An auth failure before the first event reopens the
/// source once with renewed tokens; later failures are forwarded.
///
/// `acquire`, `renew` and `isAuthFailure` must not throw an [Error]: only
/// [Exception]s are caught, by design.
final class RelayStream<T, R> {
  /// Creates a relay; nothing happens until [stream] is listened to.
  RelayStream({
    required Future<T> Function() acquire,
    required Future<T> Function(T rejected) renew,
    required Stream<R> Function(T tokens) open,
    required bool Function(Object error) isAuthFailure,
  }) : _acquire = acquire,
       _renew = renew,
       _open = open,
       _isAuthFailure = isAuthFailure {
    _controller = StreamController<R>(
      onListen: _start,
      onPause: _pause,
      onResume: _resume,
      onCancel: _cancel,
    );
  }

  final Future<T> Function() _acquire;
  final Future<T> Function(T rejected) _renew;
  final Stream<R> Function(T tokens) _open;
  final bool Function(Object error) _isAuthFailure;

  // Assigned once in the constructor body: its callbacks need `this`.
  late final StreamController<R> _controller;

  StreamSubscription<R>? _source;
  T? _used;
  bool _cancelled = false;
  bool _delivered = false;
  bool _replayed = false;

  /// The relayed stream; it supports a single subscription.
  Stream<R> get stream => _controller.stream;

  Future<void> _start() async {
    try {
      final tokens = await _acquire();
      if (_cancelled) {
        return;
      }
      _attach(tokens);
    } on Exception catch (error, stackTrace) {
      _finish(error, stackTrace);
    }
  }

  void _attach(T tokens) {
    _used = tokens;
    _source = _open(tokens).listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
    );
    if (_controller.isPaused) {
      _source?.pause();
    }
  }

  // The `_cancelled` guards below are defence in depth: a cancelled controller
  // ignores events, and they make that explicit and keep a late `acquire`
  // failure from touching it.
  void _onData(R event) {
    if (_cancelled) {
      return;
    }
    _delivered = true;
    _controller.add(event);
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (_cancelled) {
      return;
    }
    if (_delivered || _replayed || !_isAuthFailure(error)) {
      _controller.addError(error, stackTrace);
      return;
    }
    unawaited(_replay(error, stackTrace));
  }

  void _onDone() {
    if (!_cancelled && !_controller.isClosed) {
      unawaited(_controller.close());
    }
  }

  Future<void> _replay(Object error, StackTrace stackTrace) async {
    _replayed = true;
    final used = _used;
    final stale = _source;
    _source = null;
    if (used == null) {
      _finish(error, stackTrace);
      return;
    }
    try {
      await stale?.cancel();
      if (_cancelled) {
        return;
      }
      final renewed = await _renew(used);
      if (_cancelled) {
        return;
      }
      if (identical(renewed, used)) {
        _finish(error, stackTrace);
        return;
      }
      _attach(renewed);
    } on Exception catch (failure, failureTrace) {
      _finish(failure, failureTrace);
    }
  }

  void _finish(Object error, StackTrace stackTrace) {
    if (_cancelled || _controller.isClosed) {
      return;
    }
    _controller.addError(error, stackTrace);
    unawaited(_controller.close());
  }

  void _pause() => _source?.pause();

  void _resume() => _source?.resume();

  Future<void> _cancel() {
    _cancelled = true;
    final source = _source;
    _source = null;
    return source?.cancel() ?? Future<void>.value();
  }
}
