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
  /// Once the holder is closed the value still updates, but nothing is sent.
  void add(S value) {
    _value = value;
    if (!_controller.isClosed) {
      _controller.add(value);
    }
  }

  /// Completes every stream; later [add] calls only update the value.
  Future<void> close() => _controller.close();
}
