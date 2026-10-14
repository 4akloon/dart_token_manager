import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

import '../../example/recipes/skip_auth_endpoints.dart'
    show BearerDelegate, SessionClients, StandInServer, TokenEndpointAnswer;

void main() {
  // Assigned in setUp, which runs before every test.
  late StandInServer server;
  late SessionClients clients;

  setUp(() {
    server = StandInServer(lifetime: 5);
    clients = SessionClients(
      baseUrl: 'https://api.test',
      store: InMemoryTokenStore<TokenSet>(),
      adapter: server,
    );
  });

  tearDown(() => clients.dispose());

  test(
    'signIn works while signed out, because auth has no interceptor',
    () async {
      await clients.signIn('ada@example.com', 'secret');

      expect((await clients.manager.current())?.accessToken, 'access-1');
    },
  );

  test('a call on the interceptor Dio fails with NotAuthenticated before '
      'login', () async {
    await expectLater(
      clients.api.get<Object?>('/me'),
      throwsA(
        isA<DioException>().having(
          (error) => error.error,
          'error',
          isA<NotAuthenticated>(),
        ),
      ),
    );

    expect(server.paths, isEmpty);
  });

  test('a login sent through the interceptor Dio fails with '
      'NotAuthenticated', () async {
    await expectLater(
      clients.api.post<Object?>('/oauth/token'),
      throwsA(
        isA<DioException>().having(
          (error) => error.error,
          'error',
          isA<NotAuthenticated>(),
        ),
      ),
    );
  });

  test('the refresh request is sent without waiting for itself', () async {
    await clients.signIn('ada@example.com', 'secret');

    final response = await clients.api.get<Object?>('/me');

    expect(response.statusCode, 200);
    expect(server.refreshes, 1);
  });

  test('the refresh request carries no Authorization header', () async {
    await clients.signIn('ada@example.com', 'secret');

    await clients.api.get<Object?>('/me');

    expect(server.endpointAuthorizations, [null, null]);
  });

  test('a 400 from the token endpoint becomes InvalidGrant', () async {
    final failing = _FailingSession(_RefreshAnswer.rejected);

    await expectLater(
      failing.clients.manager.validToken(),
      throwsA(isA<InvalidGrant>()),
    );
  });

  test('a 400 from the token endpoint ends the session', () async {
    final failing = _FailingSession(_RefreshAnswer.rejected);

    await failing.tryRefresh();

    expect(await failing.clients.manager.current(), isNull);
  });

  test('a timeout from the token endpoint is transient', () async {
    final failing = _FailingSession(_RefreshAnswer.timedOut);

    await expectLater(
      failing.clients.manager.validToken(),
      throwsA(isA<Transient>()),
    );
  });

  test('a timeout from the token endpoint keeps the session', () async {
    final failing = _FailingSession(_RefreshAnswer.timedOut);

    await failing.tryRefresh();

    expect(await failing.clients.manager.current(), isNotNull);
  });

  test('mistake: a refresh sent through the interceptor Dio waits for '
      'itself', () async {
    final api = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = server;
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(
        TokenSet(
          accessToken: 'old',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(seconds: 5)),
        ),
      ),
      refresher: _RefreshThrough(api),
      info: const TokenSetInfo(),
    );
    addTearDown(manager.dispose);
    api.interceptors.add(
      DioTokenInterceptor<TokenSet>(
        manager: manager,
        delegate: const BearerDelegate(),
        dio: api,
      ),
    );

    await expectLater(
      api.get<Object?>('/me').timeout(const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()),
    );
  });
}

final class _RefreshThrough implements TokenRefresher<TokenSet> {
  const _RefreshThrough(this._dio);

  final Dio _dio;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    final response = await _dio.post<Object?>('/oauth/token');
    return const TokenEndpointAnswer().parse(response.data);
  }
}

/// How the token endpoint answers a refresh in [_FailingSession].
enum _RefreshAnswer { rejected, timedOut }

/// A signed-in session whose access token has expired, over a token endpoint
/// that fails every refresh.
final class _FailingSession {
  factory _FailingSession(_RefreshAnswer answer) {
    final clients = SessionClients(
      baseUrl: 'https://api.test',
      store: InMemoryTokenStore<TokenSet>(
        TokenSet(
          accessToken: 'expired',
          refreshToken: 'refresh-1',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ),
      adapter: _FailingEndpoint(answer),
    );
    addTearDown(clients.dispose);
    return _FailingSession._(clients);
  }

  _FailingSession._(this.clients);

  final SessionClients clients;

  /// Asks for a valid token and ignores the failure the tests check apart.
  Future<void> tryRefresh() async {
    try {
      await clients.manager.validToken();
    } on Exception {
      // The failure itself is checked by its own test.
    }
  }
}

final class _FailingEndpoint implements HttpClientAdapter {
  const _FailingEndpoint(this._answer);

  final _RefreshAnswer _answer;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return switch (_answer) {
      _RefreshAnswer.rejected => ResponseBody.fromString('', 400),
      _RefreshAnswer.timedOut => throw DioException.connectionTimeout(
        timeout: const Duration(seconds: 1),
        requestOptions: options,
      ),
    };
  }

  @override
  void close({bool force = false}) {}
}
