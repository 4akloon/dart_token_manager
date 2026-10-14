import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/client_fixture.dart';
import 'helpers/fake_answer.dart';
import 'helpers/test_requests.dart';

void main() {
  group('a rejected Request', () {
    test('is replayed once with refreshed tokens', () async {
      final fixture = ClientFixture();

      final response = await fixture.client.get(ClientFixture.url);

      expect(response.statusCode, 200);
      expect(fixture.inner.requests, hasLength(2));
      expect(fixture.inner.requests[1].authorization, 'Bearer fresh-1');
      expect(fixture.refresher.calls, 1);
    });

    test('is replayed with its method, headers and body', () async {
      final fixture = ClientFixture();

      await fixture.client.send(fixture.post());

      final replay = fixture.inner.requests[1];
      expect(replay.request.method, 'POST');
      expect(replay.request.headers['x-trace'], '1');
      expect(replay.text, '{"name":"ada"}');
    });

    test('has its body read before the replay is sent', () async {
      final fixture = ClientFixture();

      await fixture.client.get(ClientFixture.url);

      expect(fixture.inner.requests[1].unreadBodies, 0);
    });

    test('is returned with its body when the replay is rejected too', () async {
      final fixture = ClientFixture(answer: (_) => FakeAnswer.unauthorized);

      final response = await fixture.client.get(ClientFixture.url);

      expect(response.statusCode, 401);
      expect(response.body, 'denied');
      expect(fixture.inner.requests, hasLength(2));
    });

    test('is returned unreplayed when the manager cannot refresh', () async {
      final fixture = ClientFixture(hasRefresher: false);

      final response = await fixture.client.get(ClientFixture.url);

      expect(response.statusCode, 401);
      expect(response.body, 'denied');
      expect(fixture.inner.requests, hasLength(1));
    });
  });

  group('single flight', () {
    test('concurrent rejected requests share one refresh', () async {
      final fixture = ClientFixture();

      final responses = await Future.wait([
        fixture.client.get(ClientFixture.url),
        fixture.client.get(ClientFixture.url),
        fixture.client.get(ClientFixture.url),
      ]);

      expect(responses.map((response) => response.statusCode), [
        200,
        200,
        200,
      ]);
      expect(fixture.refresher.calls, 1);
      // Three first attempts plus one replay per rejected request.
      expect(fixture.inner.requests, hasLength(6));
    });

    test(
      'tokens replaced since the rejection are used without a refresh',
      () async {
        // late: the answer callback needs the fixture it is passed to.
        late final ClientFixture fixture;
        fixture = ClientFixture(
          answer: (sent) async {
            if (sent.authorization != 'Bearer old') {
              return FakeAnswer.ok;
            }
            await fixture.manager.setTokens(
              const TokenSet(accessToken: 'new'),
            );
            return FakeAnswer.unauthorized;
          },
        );

        final response = await fixture.client.get(ClientFixture.url);

        expect(response.statusCode, 200);
        expect(fixture.refresher.calls, 0);
        expect(fixture.inner.requests[1].authorization, 'Bearer new');
      },
    );
  });

  group('failures', () {
    test('a terminal refresh failure is thrown and ends the session', () async {
      final fixture = ClientFixture(refreshFailure: const InvalidGrant());

      await expectLater(
        fixture.client.get(ClientFixture.url),
        throwsA(isA<InvalidGrant>()),
      );
      expect(await fixture.manager.current(), isNull);
      expect(fixture.inner.requests, hasLength(1));
    });

    test(
      'a transient refresh failure is thrown and keeps the session',
      () async {
        final fixture = ClientFixture(
          refreshFailure: const Transient('offline'),
        );

        await expectLater(
          fixture.client.get(ClientFixture.url),
          throwsA(isA<Transient>()),
        );
        expect(await fixture.manager.current(), same(ClientFixture.old));
      },
    );

    test(
      'a 401 whose body fails to arrive fails the call unreplayed',
      () async {
        final fixture = ClientFixture(
          answer: (_) =>
              FakeAnswer(401, '', ClientException('connection reset')),
        );

        await expectLater(
          fixture.client.get(ClientFixture.url),
          throwsA(isA<ClientException>()),
        );
        expect(fixture.inner.requests, hasLength(1));
        expect(fixture.refresher.calls, 0);
      },
    );

    test('a network error during the replay reaches the caller', () async {
      final fixture = ClientFixture(
        answer: (sent) => sent.authorization == 'Bearer old'
            ? FakeAnswer.unauthorized
            : throw ClientException('offline'),
      );

      await expectLater(
        fixture.client.get(ClientFixture.url),
        throwsA(
          isA<ClientException>().having(
            (error) => error.message,
            'message',
            'offline',
          ),
        ),
      );
    });
  });

  group('isAuthFailure', () {
    test('decides which responses are replayed', () async {
      final fixture = ClientFixture(answer: TestRequests.forbidOld);
      final client = fixture.clientWith(
        isAuthFailure: (response) => response.statusCode == 403,
      );

      final response = await client.get(ClientFixture.url);

      expect(response.statusCode, 200);
      expect(fixture.inner.requests, hasLength(2));
    });

    test('a 403 is not replayed by default', () async {
      final fixture = ClientFixture(answer: TestRequests.forbidOld);

      final response = await fixture.client.get(ClientFixture.url);

      expect(response.statusCode, 403);
      expect(fixture.refresher.calls, 0);
    });
  });
}
