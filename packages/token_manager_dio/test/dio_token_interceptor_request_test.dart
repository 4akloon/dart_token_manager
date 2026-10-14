import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'helpers/dio_errors.dart';
import 'helpers/dio_fixture.dart';

void main() {
  const errors = DioErrors();

  test('keeps the query, the base url and the shared Dio options', () async {
    final fixture = DioFixture(ownDio: false);

    await fixture.dio.get<Object?>('/me', queryParameters: {'page': 2});

    final replay = fixture.adapter.requests.last;
    expect(replay.uri.toString(), 'https://api.test/me?page=2');
    expect(fixture.replayDio.options.baseUrl, isEmpty);
    expect(fixture.dio.options.baseUrl, 'https://api.test');
  });

  test('sends the same JSON body again', () async {
    final fixture = DioFixture();

    await fixture.dio.post<Object?>('/items', data: {'name': 'a'});

    expect(fixture.adapter.requests.map((r) => r.body), [
      '{"name":"a"}',
      '{"name":"a"}',
    ]);
  });

  test('sends a fresh clone of a FormData body', () async {
    final fixture = DioFixture();

    await fixture.dio.post<Object?>(
      '/upload',
      data: FormData.fromMap({'title': 'hello'}),
    );

    final bodies = fixture.adapter.requests.map((r) => r.body).toList();
    expect(bodies, hasLength(2));
    expect(bodies, everyElement(contains('hello')));
  });

  test('does not replay a stream body, and does not refresh', () async {
    final fixture = DioFixture();

    final call = fixture.dio.post<Object?>(
      '/upload',
      data: Stream.value(utf8.encode('payload')),
      options: Options(headers: {Headers.contentLengthHeader: 7}),
    );

    await expectLater(call, throwsA(errors.withStatus(401)));
    expect(fixture.adapter.requests, hasLength(1));
    expect(fixture.refresher.calls, 0);
  });

  test('keeps the plain response type of the request', () async {
    final fixture = DioFixture();
    fixture.adapter.successBody = 'not json';

    final response = await fixture.dio.get<String>('/text');

    expect(response.data, 'not json');
  });
}
