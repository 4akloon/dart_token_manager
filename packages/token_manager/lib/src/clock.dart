/// Supplies the current time; replace it in tests to control expiry.
class Clock {
  /// Creates a clock that reads the system time.
  const Clock();

  /// Returns the current time.
  DateTime now() => DateTime.now();
}
