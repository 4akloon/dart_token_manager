/// Supplies the current time; replace it in tests to control expiry.
///
/// The manager reads the time only through a clock, so a test can move it
/// without waiting:
///
/// ```dart
/// final class FixedClock implements Clock {
///   FixedClock(this.current);
///
///   DateTime current;
///
///   @override
///   DateTime now() => current;
/// }
/// ```
///
/// {@category testing}
class Clock {
  /// Creates a clock that reads the system time.
  const Clock();

  /// Returns the current time.
  DateTime now() => DateTime.now();
}
