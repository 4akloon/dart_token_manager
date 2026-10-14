import 'package:token_manager/src/clock.dart';

/// A clock whose time only moves when a test says so.
final class FakeClock implements Clock {
  /// Creates a clock reading [start].
  FakeClock(DateTime start) : _now = start;

  DateTime _now;

  @override
  DateTime now() => _now;

  /// Moves the clock forward by [by].
  void advance(Duration by) {
    _now = _now.add(by);
  }
}
