import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

import 'helpers/dio_fixture.dart';

/// A 0.1 delegate: only the old method.
final class _OldDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const _OldDelegate();

  @override
  void applyTokensToRequest(RequestOptions options, TokenSet? tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens?.accessToken}';
  }
}

final class _NewDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const _NewDelegate();

  @override
  void applyTo(RequestOptions options, TokenSet tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
  }
}

final class _EmptyDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const _EmptyDelegate();
}

void main() {
  const tokens = TokenSet(accessToken: 'abc', refreshToken: 'r');

  test('a delegate with only applyTokensToRequest still applies tokens', () {
    final options = RequestOptions(path: '/me');

    const _OldDelegate().applyTo(options, tokens);

    expect(options.headers['Authorization'], 'Bearer abc');
  });

  test('a delegate with only applyTo applies tokens', () {
    final options = RequestOptions(path: '/me');

    const _NewDelegate().applyTo(options, tokens);

    expect(options.headers['Authorization'], 'Bearer abc');
  });

  test('a delegate overriding neither method fails with a StateError', () {
    final options = RequestOptions(path: '/me');

    expect(
      () => const _EmptyDelegate().applyTo(options, tokens),
      throwsStateError,
    );
  });

  test(
    'the interceptor replays a request with an old-style delegate',
    () async {
      final fixture = DioFixture(delegate: const _OldDelegate());

      final response = await fixture.dio.get<Object?>('/me');

      expect(response.statusCode, 200);
      expect(fixture.adapter.requests, hasLength(2));
    },
  );

  test('the interceptor replays a request with a new-style delegate', () async {
    final fixture = DioFixture(delegate: const _NewDelegate());

    final response = await fixture.dio.get<Object?>('/me');

    expect(response.statusCode, 200);
    expect(fixture.adapter.requests, hasLength(2));
  });
}
