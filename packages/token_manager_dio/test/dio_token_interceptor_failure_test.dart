import 'dart:async';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/dio_errors.dart';
import 'helpers/dio_fixture.dart';

void main() {
  const errors = DioErrors();

  group('when the tokens cannot be renewed', () {
    test('surfaces InvalidGrant and signs the session out', () async {
      final fixture = DioFixture(refreshFailure: const InvalidGrant());

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(
        call,
        throwsA(errors.wrapping(isA<InvalidGrant>(), status: 401)),
      );
      expect(await fixture.manager.current(), isNull);
      expect(fixture.adapter.requests, hasLength(1));
    });

    test('surfaces a transient failure and keeps the session', () async {
      final fixture = DioFixture(refreshFailure: const Transient('offline'));

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(
        call,
        throwsA(errors.wrapping(isA<Transient>(), status: 401)),
      );
      expect(await fixture.manager.current(), DioFixture.initial);
    });
  });

  group('when the session changed while the request was in flight', () {
    Future<Future<Response<Object?>>> startHeldRequest(
      DioFixture fixture,
    ) async {
      fixture.adapter.gate = Completer<void>();
      final call = fixture.dio.get<Object?>('/me');
      await pumpEventQueue();
      expect(fixture.adapter.requests, hasLength(1));
      return call;
    }

    test('replays with the newer tokens without a second refresh', () async {
      final fixture = DioFixture();
      final call = await startHeldRequest(fixture);

      await fixture.manager.setTokens(
        const TokenSet(accessToken: 'new', refreshToken: 'refresh-2'),
      );
      fixture.adapter.gate?.complete();
      final response = await call;

      expect(response.statusCode, 200);
      expect(fixture.refresher.calls, 0);
      expect(fixture.adapter.requests.map((r) => r.authorization), [
        'Bearer old',
        'Bearer new',
      ]);
    });

    test('surfaces NotAuthenticated after a logout', () async {
      final fixture = DioFixture();
      final call = await startHeldRequest(fixture);
      final outcome = expectLater(
        call,
        throwsA(errors.wrapping(isA<NotAuthenticated>(), status: 401)),
      );

      await fixture.manager.logout();
      fixture.adapter.gate?.complete();

      await outcome;
      expect(fixture.adapter.requests, hasLength(1));
    });
  });
}
