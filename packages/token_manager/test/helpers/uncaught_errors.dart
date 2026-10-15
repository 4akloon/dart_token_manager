import 'dart:async';

/// Runs a body in a zone and reports the errors nobody handled.
final class UncaughtErrors {
  /// Creates the collector.
  const UncaughtErrors();

  /// Runs [body], lets the event queue settle and returns the errors that
  /// reached the zone's uncaught-error handler, those of [body] included.
  ///
  /// Keep `expect` calls out of [body]: a failed one would be collected here
  /// instead of failing the test.
  Future<List<Object>> during(Future<void> Function() body) async {
    final errors = <Object>[];
    final finished = Completer<void>();
    unawaited(
      runZonedGuarded(() async {
        try {
          await body();
        } finally {
          finished.complete();
        }
      }, (error, stack) => errors.add(error)),
    );
    await finished.future;
    await Future<void>.delayed(Duration.zero);
    return errors;
  }
}
