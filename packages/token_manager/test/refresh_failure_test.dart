import 'package:test/test.dart';
import 'package:token_manager/src/not_authenticated.dart';
import 'package:token_manager/src/refresh_failure.dart';

void main() {
  test('InvalidGrant is a RefreshFailure and an Exception', () {
    const failure = InvalidGrant();

    expect(failure, isA<RefreshFailure>());
    expect(failure, isA<Exception>());
  });

  test('Transient keeps the cause and mentions it in its message', () {
    final cause = Exception('offline');
    final failure = Transient(cause);

    expect(failure.cause, same(cause));
    expect(failure.toString(), contains('offline'));
  });

  test('NotAuthenticated is an Exception', () {
    expect(const NotAuthenticated(), isA<Exception>());
  });
}
