import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/dio_errors.dart';
import 'helpers/dio_fixture.dart';

void main() {
  const errors = DioErrors();

  group('attaching the token', () {
    test('sends the current access token in the delegate header', () async {
      final fixture = DioFixture(accepted: 'Bearer old');

      final response = await fixture.dio.get<Object?>('/me');

      expect(response.statusCode, 200);
      expect(fixture.adapter.requests.single.authorization, 'Bearer old');
    });

    test('fails with NotAuthenticated when logged out', () async {
      final fixture = DioFixture(signedIn: false);

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(
        call,
        throwsA(errors.wrapping(isA<NotAuthenticated>())),
      );
      expect(fixture.adapter.requests, isEmpty);
    });
  });

  group('replaying after a 401', () {
    test('sends the request again once with the refreshed token', () async {
      final fixture = DioFixture();

      final response = await fixture.dio.get<Object?>('/me');

      expect(response.statusCode, 200);
      expect(fixture.adapter.requests.map((r) => r.authorization), [
        'Bearer old',
        'Bearer new',
      ]);
      expect(fixture.refresher.calls, 1);
    });

    test('replays exactly once when the server keeps answering 401', () async {
      final fixture = DioFixture(accepted: 'Bearer never');

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(call, throwsA(errors.withStatus(401)));
      expect(fixture.adapter.requests, hasLength(2));
      expect(fixture.refresher.calls, 1);
    });

    test('replays exactly once through a separate Dio as well', () async {
      final fixture = DioFixture(accepted: 'Bearer never', ownDio: false);

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(call, throwsA(errors.withStatus(401)));
      expect(fixture.adapter.requests, hasLength(2));
    });

    test('shares one refresh between concurrent requests', () async {
      final fixture = DioFixture();

      final responses = await Future.wait([
        fixture.dio.get<Object?>('/a'),
        fixture.dio.get<Object?>('/b'),
        fixture.dio.get<Object?>('/c'),
      ]);

      expect(responses.map((r) => r.statusCode), [200, 200, 200]);
      expect(fixture.refresher.calls, 1);
      expect(fixture.adapter.requests, hasLength(6));
    });

    test('passes the 401 on when the manager cannot refresh', () async {
      final fixture = DioFixture(withRefresher: false);

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(call, throwsA(errors.withStatus(401)));
      expect(fixture.adapter.requests, hasLength(1));
    });
  });
}
