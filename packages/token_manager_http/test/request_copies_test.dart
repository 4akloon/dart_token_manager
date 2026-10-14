import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager_http/src/request_copies.dart';

/// A [Request] subclass, which may build its body in `finalize`.
final class _SignedRequest extends Request {
  _SignedRequest(super.method, super.url);
}

void main() {
  const copies = RequestCopies();
  final url = Uri.parse('https://api.example.com/items');
  const token = {'Authorization': 'Bearer t'};

  group('asReplayable', () {
    test('accepts a Request', () {
      final request = Request('GET', url);

      expect(copies.asReplayable(request), same(request));
    });

    test('accepts an AbortableRequest', () {
      final request = AbortableRequest('GET', url);

      expect(copies.asReplayable(request), same(request));
    });

    test('rejects a StreamedRequest', () {
      expect(copies.asReplayable(StreamedRequest('POST', url)), isNull);
    });

    test('rejects a MultipartRequest', () {
      expect(copies.asReplayable(MultipartRequest('POST', url)), isNull);
    });

    test('rejects another subclass of Request', () {
      expect(copies.asReplayable(_SignedRequest('GET', url)), isNull);
    });
  });

  group('copyOf', () {
    test('copies the method, url, headers and body', () {
      final original = Request('PUT', url)
        ..headers['X-Trace'] = '1'
        ..body = 'hello';

      final copy = copies.copyOf(original, token);

      expect(copy.method, 'PUT');
      expect(copy.url, url);
      expect(copy.headers['x-trace'], '1');
      expect(copy.headers['content-type'], original.headers['content-type']);
      expect(copy.body, 'hello');
    });

    test('adds the token header and leaves the original unchanged', () {
      final original = Request('GET', url);

      final copy = copies.copyOf(original, token);

      expect(copy.headers['authorization'], 'Bearer t');
      expect(original.headers, isEmpty);
      expect(original.finalized, isFalse);
    });

    test('the token header replaces the same header in any case', () {
      final original = Request('GET', url)
        ..headers['authorization'] = 'Bearer stale';

      final copy = copies.copyOf(original, token);

      expect(copy.headers, hasLength(1));
      expect(copy.headers['Authorization'], 'Bearer t');
      expect(original.headers['authorization'], 'Bearer stale');
    });

    test('copies the redirect and connection settings', () {
      final original = Request('GET', url)
        ..followRedirects = false
        ..maxRedirects = 2
        ..persistentConnection = false;

      final copy = copies.copyOf(original, token);

      expect(copy.followRedirects, isFalse);
      expect(copy.maxRedirects, 2);
      expect(copy.persistentConnection, isFalse);
    });

    test('copies an encoding that the content type does not name', () {
      final original = Request('POST', url)
        ..encoding = latin1
        ..bodyBytes = [0xE9];

      final copy = copies.copyOf(original, token);

      expect(copy.encoding, latin1);
      expect(copy.headers.containsKey('content-type'), isFalse);
      expect(copy.bodyBytes, [0xE9]);
    });

    test('keeps a content type that names its charset as it was', () {
      final original = Request('POST', url)
        ..headers['content-type'] = 'text/plain; charset=UTF-8';

      final copy = copies.copyOf(original, token);

      expect(copy.headers['content-type'], 'text/plain; charset=UTF-8');
    });

    test('copies a request whose charset is unknown', () {
      final original = Request('POST', url)
        ..headers['content-type'] = 'text/plain; charset=x-unknown'
        ..bodyBytes = [1, 2];

      final copy = copies.copyOf(original, token);

      expect(copy.headers['content-type'], 'text/plain; charset=x-unknown');
      expect(copy.bodyBytes, [1, 2]);
    });

    test('keeps the abort trigger of an AbortableRequest', () {
      final trigger = Completer<void>().future;
      final original = AbortableRequest('GET', url, abortTrigger: trigger);

      final copy = copies.copyOf(original, token);

      expect(
        copy,
        isA<AbortableRequest>().having(
          (request) => request.abortTrigger,
          'abortTrigger',
          same(trigger),
        ),
      );
    });
  });

  group('streamOf', () {
    test(
      'streams the body of a StreamedRequest with the token header',
      () async {
        final original = StreamedRequest('POST', url)
          ..headers['X-Trace'] = '1'
          ..contentLength = 5;
        original.sink.add(utf8.encode('hello'));
        unawaited(original.sink.close());

        final copy = copies.streamOf(original, token);

        expect(copy.headers['authorization'], 'Bearer t');
        expect(copy.headers['x-trace'], '1');
        expect(copy.contentLength, 5);
        expect(await copy.finalize().bytesToString(), 'hello');
        expect(original.headers.containsKey('authorization'), isFalse);
      },
    );

    test('keeps the multipart content type and body', () async {
      final original = MultipartRequest('POST', url)..fields['name'] = 'ada';

      final copy = copies.streamOf(original, token);

      expect(
        copy.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(copy.contentLength, original.contentLength);
      expect(await copy.finalize().bytesToString(), contains('ada'));
    });

    test('keeps the abort trigger of an abortable request', () {
      final trigger = Completer<void>().future;
      final original = AbortableStreamedRequest(
        'POST',
        url,
        abortTrigger: trigger,
      );
      unawaited(original.sink.close());

      final copy = copies.streamOf(original, token);

      expect(
        copy,
        isA<AbortableStreamedRequest>().having(
          (request) => request.abortTrigger,
          'abortTrigger',
          same(trigger),
        ),
      );
    });

    test('forwards an error of the original body', () async {
      final original = StreamedRequest('POST', url);
      original.sink.addError(const FormatException('broken'));
      unawaited(original.sink.close());

      final copy = copies.streamOf(original, token);

      await expectLater(copy.finalize().toBytes(), throwsFormatException);
    });
  });
}
