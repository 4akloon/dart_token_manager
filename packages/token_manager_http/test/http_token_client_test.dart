import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

import 'helpers/client_fixture.dart';
import 'helpers/recording_client.dart';
import 'helpers/test_requests.dart';

void main() {
  group('with tokens', () {
    test('attaches the bearer header of the current tokens', () async {
      final fixture = ClientFixture(answer: TestRequests.alwaysOk);

      await fixture.client.get(ClientFixture.url);

      expect(fixture.inner.requests.single.authorization, 'Bearer old');
    });

    test('returns the response of the inner client', () async {
      final fixture = ClientFixture(answer: TestRequests.alwaysOk);

      final response = await fixture.client.get(ClientFixture.url);

      expect(response.statusCode, 200);
      expect(response.body, 'ok');
    });

    test('sends the method, headers and body of the request', () async {
      final fixture = ClientFixture(answer: TestRequests.alwaysOk);

      await fixture.client.send(fixture.post());

      final sent = fixture.inner.requests.single;
      expect(sent.request.method, 'POST');
      expect(sent.request.headers['x-trace'], '1');
      expect(sent.text, '{"name":"ada"}');
    });

    test('leaves the caller request without the token header', () async {
      final fixture = ClientFixture(answer: TestRequests.alwaysOk);
      final request = fixture.post();

      await fixture.client.send(request);

      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.finalized, isFalse);
    });

    test('the token header replaces a header the caller set', () async {
      final fixture = ClientFixture(answer: TestRequests.alwaysOk);
      final request = fixture.post()..headers['Authorization'] = 'Bearer stale';

      await fixture.client.send(request);

      expect(fixture.inner.requests.single.authorization, 'Bearer old');
      expect(request.headers['authorization'], 'Bearer stale');
    });

    test(
      'the token header replaces a lower-case header the caller set',
      () async {
        final fixture = ClientFixture(answer: TestRequests.alwaysOk);
        final request = fixture.post()
          ..headers['authorization'] = 'Bearer stale';

        await fixture.client.send(request);

        expect(fixture.inner.requests.single.authorization, 'Bearer old');
        expect(request.headers['authorization'], 'Bearer stale');
      },
    );
  });

  group('headers', () {
    test('sends the headers the builder returns', () async {
      final fixture = ClientFixture(answer: TestRequests.alwaysOk);
      final client = fixture.clientWith(
        headers: (tokens) => {'X-Api-Key': tokens.accessToken},
      );

      await client.get(ClientFixture.url);

      final sent = fixture.inner.requests.single;
      expect(sent.request.headers['x-api-key'], 'old');
      expect(sent.authorization, isNull);
    });

    test('works with any token type that has a headers builder', () async {
      final inner = RecordingClient(answer: TestRequests.alwaysOk);
      final client = HttpTokenClient<String>(
        manager: TokenManager<String>.create(
          store: InMemoryTokenStore<String>('abc'),
        ),
        inner: inner,
        headers: (tokens) => {'Authorization': 'Token $tokens'},
      );

      await client.get(ClientFixture.url);

      expect(inner.requests.single.authorization, 'Token abc');
    });

    test('needs a headers builder unless the token type is TokenSet', () {
      expect(
        () => HttpTokenClient<String>(
          manager: TokenManager<String>.create(
            store: InMemoryTokenStore<String>(),
          ),
          inner: RecordingClient(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('without tokens', () {
    test('a request shouldAuthorize declines is sent unchanged', () async {
      final fixture = ClientFixture(
        isSignedIn: false,
        answer: TestRequests.alwaysOk,
      );
      final client = fixture.clientWith(
        shouldAuthorize: (request) => request.url.path != '/login',
      );
      final login = Request('POST', Uri.parse('https://api.example.com/login'));

      await client.send(login);

      expect(fixture.inner.requests.single.request, same(login));
      expect(fixture.inner.requests.single.authorization, isNull);
    });

    test('fails with NotAuthenticated and sends nothing', () async {
      final fixture = ClientFixture(
        isSignedIn: false,
        answer: TestRequests.alwaysOk,
      );

      await expectLater(
        fixture.client.get(ClientFixture.url),
        throwsA(isA<NotAuthenticated>()),
      );
      expect(fixture.inner.requests, isEmpty);
    });
  });

  group('streamed bodies', () {
    test('a StreamedRequest is sent with the token header', () async {
      final fixture = ClientFixture(answer: TestRequests.alwaysOk);
      final request = TestRequests.streamed('chunk');

      await fixture.client.send(request);

      final sent = fixture.inner.requests.single;
      expect(sent.authorization, 'Bearer old');
      expect(sent.text, 'chunk');
      expect(request.headers.containsKey('authorization'), isFalse);
    });

    test('a MultipartRequest keeps its boundary and fields', () async {
      final fixture = ClientFixture(answer: TestRequests.alwaysOk);
      final request = MultipartRequest('POST', ClientFixture.url)
        ..fields['name'] = 'ada';

      await fixture.client.send(request);

      final sent = fixture.inner.requests.single;
      expect(
        sent.request.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(sent.text, contains('ada'));
      expect(sent.authorization, 'Bearer old');
    });
  });

  group('a request sent once', () {
    test('a rejected StreamedRequest is returned as is', () async {
      final fixture = ClientFixture();

      final response = await fixture.client.send(
        TestRequests.streamed('chunk'),
      );

      expect(response.statusCode, 401);
      expect(await response.stream.bytesToString(), 'denied');
      expect(fixture.inner.requests, hasLength(1));
    });

    test('a rejected MultipartRequest is returned as is', () async {
      final fixture = ClientFixture();
      final request = MultipartRequest('POST', ClientFixture.url)
        ..fields['name'] = 'ada';

      final response = await fixture.client.send(request);

      expect(response.statusCode, 401);
      expect(fixture.inner.requests, hasLength(1));
    });

    test('its rejection starts a refresh for the next request', () async {
      final fixture = ClientFixture();

      await fixture.client.send(TestRequests.streamed('chunk'));
      await pumpEventQueue();
      final next = await fixture.client.get(ClientFixture.url);

      expect(fixture.refresher.calls, 1);
      expect(next.statusCode, 200);
      expect(fixture.inner.requests, hasLength(2));
      expect(fixture.inner.requests.last.authorization, 'Bearer fresh-1');
    });

    test(
      'a terminal failure of that refresh ends the session without failing '
      'the call',
      () async {
        final fixture = ClientFixture(refreshFailure: const InvalidGrant());

        final response = await fixture.client.send(
          TestRequests.streamed('chunk'),
        );
        await pumpEventQueue();

        expect(response.statusCode, 401);
        expect(await fixture.manager.current(), isNull);
      },
    );
  });
}
