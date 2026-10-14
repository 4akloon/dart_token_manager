/// What the fake inner client answers: a status, a body text, and an
/// optional failure of the body stream.
final class FakeAnswer {
  /// Creates an answer whose body fails with [failure] after [body] when it
  /// is set.
  const FakeAnswer(this.status, [this.body = '', this.failure]);

  /// A 200 with the body `ok`.
  static const FakeAnswer ok = FakeAnswer(200, 'ok');

  /// A 401 with the body `denied`.
  static const FakeAnswer unauthorized = FakeAnswer(401, 'denied');

  /// The status code.
  final int status;

  /// The body text.
  final String body;

  /// What the body stream fails with after [body]; `null` ends it normally.
  final Exception? failure;
}
