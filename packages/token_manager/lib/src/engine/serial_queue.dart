import 'dart:async';

/// Runs asynchronous actions one at a time, in the order they were queued.
final class SerialQueue {
  Future<void> _tail = Future<void>.value();

  /// Runs [action] after every earlier action has finished.
  ///
  /// The result or error of [action] is returned to the caller; a failure
  /// never blocks the actions queued after it.
  Future<R> run<R>(Future<R> Function() action) {
    final result = _tail.then<R>((_) => action());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
