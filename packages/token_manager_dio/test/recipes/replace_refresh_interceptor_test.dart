import 'dart:io';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

import '../../example/recipes/replace_refresh_interceptor.dart'
    show ApiClient, BearerDelegate, StandInRefresher, StandInServer;

void main() {
  // Assigned in setUp, which runs before every test.
  late StandInRefresher refresher;
  late StandInServer server;
  late TokenManager<TokenSet> manager;
  late ApiClient api;

  setUp(() {
    refresher = StandInRefresher();
    server = StandInServer();
    manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(_Tokens.stale),
      refresher: refresher,
    );
    api = ApiClient(
      manager: manager,
      baseUrl: 'https://api.test',
      adapter: server,
    );
  });

  tearDown(() => manager.dispose());

  test('parallel 401s share one refresh', () async {
    await Future.wait([
      api.dio.get<Object?>('/a'),
      api.dio.get<Object?>('/b'),
      api.dio.get<Object?>('/c'),
    ]);

    expect(refresher.calls, 1);
  });

  test('each rejected request is replayed once with the new token', () async {
    final responses = await Future.wait([
      api.dio.get<Object?>('/a'),
      api.dio.get<Object?>('/b'),
    ]);

    expect(responses.map((response) => response.statusCode), [200, 200]);
    expect(server.received, [
      'Bearer stale',
      'Bearer stale',
      'Bearer fresh',
      'Bearer fresh',
    ]);
  });

  test('three parallel requests are each sent twice', () async {
    await Future.wait([
      api.dio.get<Object?>('/a'),
      api.dio.get<Object?>('/b'),
      api.dio.get<Object?>('/c'),
    ]);

    expect(server.received, [
      ...List.filled(3, 'Bearer stale'),
      ...List.filled(3, 'Bearer fresh'),
    ]);
  });

  test('a refresh that renews nothing sends the request only once', () async {
    final stubborn = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(_Tokens.stale),
      refresher: _SameTokenRefresher(),
    );
    addTearDown(stubborn.dispose);
    final client = ApiClient(
      manager: stubborn,
      baseUrl: 'https://api.test',
      adapter: server,
    );

    await expectLater(
      client.dio.get<Object?>('/a'),
      throwsA(isA<DioException>()),
    );

    expect(server.received, ['Bearer stale']);
  });

  test('a refresh that renews nothing returns the original 401', () async {
    final stubborn = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(_Tokens.stale),
      refresher: _SameTokenRefresher(),
    );
    addTearDown(stubborn.dispose);
    final client = ApiClient(
      manager: stubborn,
      baseUrl: 'https://api.test',
      adapter: server,
    );

    await expectLater(
      client.dio.get<Object?>('/a'),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'status code',
          401,
        ),
      ),
    );
  });

  test('a dead refresh token reaches the caller as InvalidGrant', () async {
    final client = _DeadSession(server);

    await expectLater(
      client.api.dio.get<Object?>('/a'),
      throwsA(
        isA<DioException>().having(
          (error) => error.error,
          'error',
          isA<InvalidGrant>(),
        ),
      ),
    );
  });

  test('a dead refresh token signs the session out', () async {
    final client = _DeadSession(server);

    try {
      await client.api.dio.get<Object?>('/a');
    } on DioException {
      // The failure itself is checked by the test above.
    }

    expect(await client.manager.current(), isNull);
  });

  test('a POST is replayed like a GET', () async {
    final response = await api.dio.post<Object?>('/a', data: {'x': 1});

    expect(response.statusCode, 200);
    expect(server.received, ['Bearer stale', 'Bearer fresh']);
  });

  test('a stream body is not replayed and starts no refresh', () async {
    await expectLater(
      api.dio.post<Object?>(
        '/a',
        data: Stream<List<int>>.value([1, 2, 3]),
        options: Options(headers: {Headers.contentLengthHeader: 3}),
      ),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'status code',
          401,
        ),
      ),
    );

    expect(server.received, ['Bearer stale']);
    expect(refresher.calls, 0);
  });

  test('without dio: the replay does not use the adapter of the client', () {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = server;
    dio.interceptors.add(
      DioTokenInterceptor<TokenSet>(
        manager: manager,
        delegate: const BearerDelegate(),
      ),
    );

    // Any client the replay builds is refused here, so nothing leaves the
    // machine; the refusal shows that a default adapter sent the replay.
    var isRefused = false;
    return HttpOverrides.runZoned(
      () async {
        await expectLater(
          dio.get<Object?>('/a'),
          throwsA(isA<DioException>()),
        );

        expect(isRefused, isTrue);
        expect(server.received, ['Bearer stale']);
      },
      createHttpClient: (_) {
        isRefused = true;
        throw const SocketException('no network');
      },
    );
  });
}

final class _Tokens {
  static const stale = TokenSet(
    accessToken: 'stale',
    refreshToken: 'refresh-1',
  );
}

/// A client whose refresh token the server has revoked.
final class _DeadSession {
  factory _DeadSession(StandInServer server) {
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(_Tokens.stale),
      refresher: _DeadRefresher(),
    );
    addTearDown(manager.dispose);
    final api = ApiClient(
      manager: manager,
      baseUrl: 'https://api.test',
      adapter: server,
    );
    return _DeadSession._(api, manager);
  }

  _DeadSession._(this.api, this.manager);

  final ApiClient api;
  final TokenManager<TokenSet> manager;
}

final class _SameTokenRefresher implements TokenRefresher<TokenSet> {
  @override
  Future<TokenSet> refresh(TokenSet current) async => current;
}

final class _DeadRefresher implements TokenRefresher<TokenSet> {
  @override
  Future<TokenSet> refresh(TokenSet current) async {
    throw const InvalidGrant();
  }
}
