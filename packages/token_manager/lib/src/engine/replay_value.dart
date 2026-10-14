import 'dart:async';

/// Holds a value and a stream that replays the latest value to each listener.
final class ReplayValue<S> {
  /// Creates a holder whose first value is [initial].
  ReplayValue(S initial) : _value = initial;

  S _value;
  final StreamController<S> _controller = StreamController<S>.broadcast();

  /// The latest value.
  S get value => _value;

  /// A stream that emits the latest value on listen, then every later one.
  Stream<S> get stream => Stream<S>.multi((listener) {
    listener.add(_value);
    final subscription = _controller.stream.listen(
      listener.add,
      onDone: listener.close,
    );
    listener.onCancel = subscription.cancel;
  });

  /// Makes [value] the latest value and sends it to the listeners.
  ///
  /// Does nothing once the holder is closed.
  void add(S value) {
    if (_controller.isClosed) {
      return;
    }
    _value = value;
    _controller.add(value);
  }

  /// Completes every stream; later [add] calls are ignored.
  Future<void> close() => _controller.close();
}
