import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:token_manager_dio/src/request_marks.dart';

void main() {
  const marks = RequestMarks<String>();

  RequestOptions request({Object? data}) {
    return RequestOptions(path: '/me', data: data);
  }

  test('knows no tokens for a request it did not mark', () {
    expect(marks.tokensOf(request()), isNull);
  });

  test('returns the tokens it recorded', () {
    final options = request();

    marks.recordTokens(options, 'old');

    expect(marks.tokensOf(options), 'old');
  });

  test('a recorded request is not a replay', () {
    final options = request();

    marks.recordTokens(options, 'old');

    expect(marks.isReplay(options), isFalse);
  });

  test('a stream body cannot be replayed', () {
    final options = request(data: Stream.value(utf8.encode('x')));

    expect(marks.canReplay(options), isFalse);
  });

  test('text, JSON and FormData bodies can be replayed', () {
    expect(marks.canReplay(request(data: 'x')), isTrue);
    expect(marks.canReplay(request(data: {'a': 1})), isTrue);
    expect(marks.canReplay(request(data: FormData())), isTrue);
  });

  group('the replay copy', () {
    test('is marked and carries the new tokens', () {
      final options = request()..extra['keep'] = 1;
      marks.recordTokens(options, 'old');

      final replay = marks.replayOf(options, 'new');

      expect(marks.isReplay(replay), isTrue);
      expect(marks.tokensOf(replay), 'new');
      expect(replay.extra['keep'], 1);
    });

    test('leaves the original request untouched', () {
      final options = request();
      marks.recordTokens(options, 'old');

      marks.replayOf(options, 'new');

      expect(marks.isReplay(options), isFalse);
      expect(marks.tokensOf(options), 'old');
    });

    test('clones a FormData body', () {
      final form = FormData.fromMap({'title': 'hello'});

      final replay = marks.replayOf(request(data: form), 'new');

      expect(replay.data, isA<FormData>());
      expect(replay.data, isNot(same(form)));
    });
  });
}
