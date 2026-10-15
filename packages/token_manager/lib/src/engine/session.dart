import 'dart:async';

import '../auth_state.dart';
import 'replay_value.dart';
import 'serial_queue.dart';

/// The state, epoch, write queue and refresh flight of one engine.
///
/// The epoch counts sessions: work that started in an older one is stale.
final class Session<T> {
  final SerialQueue _queue = SerialQueue();
  final ReplayValue<AuthState<T>> _states = ReplayValue<AuthState<T>>(
    Unauthenticated<T>(),
  );
  Future<T>? _flight;
  int _epoch = 0;

  /// The current session number.
  int get epoch => _epoch;

  /// Runs the writes of this session one at a time.
  SerialQueue get queue => _queue;

  /// Emits the latest state on listen, then every change.
  Stream<AuthState<T>> get states => _states.stream;

  /// The latest state.
  AuthState<T> get state => _states.value;

  /// The refresh in flight, or `null`.
  Future<T>? get flight => _flight;

  /// Whether [close] was called.
  bool get isClosed => _states.isClosed;

  /// Makes [next] the latest state and sends it to the listeners.
  void emit(AuthState<T> next) {
    _states.add(next);
  }

  /// Invalidates work started for the previous session, flight included.
  ///
  /// The old flight keeps running so that its own waiters still resolve.
  void startNewSession() {
    _epoch++;
    _flight = null;
  }

  /// Makes [flight] the one in flight until it ends or the session changes.
  void track(Future<T> flight) {
    _flight = flight;
    void forget() {
      if (identical(_flight, flight)) {
        _flight = null;
      }
    }

    flight.then<void>((_) => forget(), onError: (_) => forget());
  }

  /// Closes [states]; [state] keeps following [emit], but nothing is sent.
  Future<void> close() => _states.close();
}
