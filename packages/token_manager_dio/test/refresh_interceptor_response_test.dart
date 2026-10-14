import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

import 'helpers/dio_errors.dart';
import 'helpers/dio_fixture.dart';

final class _NeverRefreshDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const _NeverRefreshDelegate();

  @override
  void applyTokensToRequest(RequestOptions options, TokenSet? tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens?.accessToken}';
  }

  @override
  bool shouldRefresh(Response<Object?>? response) => false;
}

void main() {
  const errors = DioErrors();

  group('which failures are replayed', () {
    test('replays a 401 that validateStatus accepted', () async {
      final fixture = DioFixture();

      final response = await fixture.dio.get<Object?>(
        '/me',
        options: Options(validateStatus: (_) => true),
      );

      expect(response.statusCode, 200);
      expect(fixture.adapter.requests, hasLength(2));
      expect(fixture.refresher.calls, 1);
    });

    test('replays an accepted 401 once when the server keeps it up', () async {
      final fixture = DioFixture(accepted: 'Bearer never');

      final response = await fixture.dio.get<Object?>(
        '/me',
        options: Options(validateStatus: (_) => true),
      );

      expect(response.statusCode, 401);
      expect(fixture.adapter.requests, hasLength(2));
    });

    test('follows the delegate when it refuses to refresh', () async {
      final fixture = DioFixture(delegate: const _NeverRefreshDelegate());

      final call = fixture.dio.get<Object?>('/me');

      await expectLater(call, throwsA(errors.withStatus(401)));
      expect(fixture.adapter.requests, hasLength(1));
      expect(fixture.refresher.calls, 0);
    });
  });

  group('a refresh failure on an accepted 401', () {
    test(
      'keeps the session and refreshes once on a transient failure',
      () async {
        final fixture = DioFixture(refreshFailure: const Transient('offline'));

        final call = fixture.dio.get<Object?>(
          '/me',
          options: Options(validateStatus: (_) => true),
        );

        await expectLater(
          call,
          throwsA(errors.wrapping(isA<Transient>(), status: 401)),
        );
        expect(fixture.refresher.calls, 1);
        expect(await fixture.manager.current(), DioFixture.initial);
      },
    );

    test('reports InvalidGrant and logs out', () async {
      final fixture = DioFixture(refreshFailure: const InvalidGrant());

      final call = fixture.dio.get<Object?>(
        '/me',
        options: Options(validateStatus: (_) => true),
      );

      await expectLater(
        call,
        throwsA(errors.wrapping(isA<InvalidGrant>(), status: 401)),
      );
      expect(await fixture.manager.current(), isNull);
    });
  });
}
