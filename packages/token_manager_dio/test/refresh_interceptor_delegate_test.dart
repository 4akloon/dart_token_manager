import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'helpers/bearer_delegate.dart';

void main() {
  const delegate = BearerDelegate();

  Response<Object?> answer(int status) {
    return Response<Object?>(
      requestOptions: RequestOptions(path: '/me'),
      statusCode: status,
    );
  }

  test('asks for a refresh on a 401', () {
    expect(delegate.shouldRefresh(answer(401)), isTrue);
  });

  test('does not ask for a refresh on other statuses', () {
    expect(delegate.shouldRefresh(answer(200)), isFalse);
    expect(delegate.shouldRefresh(answer(403)), isFalse);
  });

  test('does not ask for a refresh without a response', () {
    expect(delegate.shouldRefresh(null), isFalse);
  });
}
