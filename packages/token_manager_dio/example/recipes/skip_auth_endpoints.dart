import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

/// Writes the access token into the `Authorization` header.
final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  /// Creates the delegate.
  const BearerDelegate();

  @override
  void applyTo(RequestOptions options, TokenSet tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
  }
}

/// Reads the answer of the token endpoint.
final class TokenEndpointAnswer {
  /// Creates the reader.
  const TokenEndpointAnswer();

  /// Returns the tokens in [body], or throws a [FormatException].
  TokenSet parse(Object? body) {
    return switch (body) {
      {
        'access_token': final String access,
        'refresh_token': final String refresh,
        'expires_in': final int seconds,
      } =>
        TokenSet(
          accessToken: access,
          refreshToken: refresh,
          expiresAt: DateTime.now().add(Duration(seconds: seconds)),
        ),
      _ => throw const FormatException('Unreadable token endpoint answer'),
    };
  }
}

/// Refreshes through [_authDio], which has no token interceptor.
final class DioTokenRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher that posts to `/oauth/token` with [_authDio].
  const DioTokenRefresher(this._authDio);

  final Dio _authDio;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    try {
      final response = await _authDio.post<Object?>(
        '/oauth/token',
        data: {
          'grant_type': 'refresh_token',
          'refresh_token': current.refreshToken,
        },
      );
      return const TokenEndpointAnswer().parse(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 400) {
        // The server rejected the refresh token for good.
        throw const InvalidGrant();
      }
      rethrow; // anything else, such as a timeout, is Transient
    }
  }
}

/// The two clients of an app: [auth] for the login and refresh endpoints,
/// [api] for everything else.
final class SessionClients {
  /// Creates both clients over [store]; [adapter] replaces the network.
  factory SessionClients({
    required String baseUrl,
    required TokenStore<TokenSet> store,
    HttpClientAdapter? adapter,
  }) {
    // No interceptor on this one: its requests never ask for tokens.
    final auth = Dio(BaseOptions(baseUrl: baseUrl));
    final api = Dio(BaseOptions(baseUrl: baseUrl));
    if (adapter != null) {
      auth.httpClientAdapter = adapter;
      api.httpClientAdapter = adapter;
    }
    final manager = TokenManager<TokenSet>.create(
      store: store,
      refresher: DioTokenRefresher(auth),
      info: const TokenSetInfo(),
    );
    api.interceptors.add(
      DioTokenInterceptor<TokenSet>(
        manager: manager,
        delegate: const BearerDelegate(),
        dio: api,
      ),
    );
    return SessionClients._(auth, api, manager);
  }

  const SessionClients._(this.auth, this.api, this.manager);

  /// Sends the login and the refresh; never carries tokens.
  final Dio auth;

  /// Sends every authorized call.
  final Dio api;

  /// The manager behind [api].
  final TokenManager<TokenSet> manager;

  /// Signs in through [auth] and stores the tokens.
  Future<void> signIn(String email, String password) async {
    final response = await auth.post<Object?>(
      '/oauth/token',
      data: {'grant_type': 'password', 'username': email, 'password': password},
    );
    await manager.setTokens(const TokenEndpointAnswer().parse(response.data));
  }

  /// Releases the manager.
  Future<void> dispose() => manager.dispose();
}

// ---- Stand-in for your server, so this file runs without a network.

/// Serves `/oauth/token` and `/me`; access tokens live [lifetime] seconds.
final class StandInServer implements HttpClientAdapter {
  /// Creates a server that issues tokens valid for [lifetime] seconds.
  StandInServer({this.lifetime = 3600});

  /// The `expires_in` of an issued access token.
  final int lifetime;

  /// The path of every request, in arrival order.
  final List<String> paths = [];

  /// The `Authorization` header of every request to `/oauth/token`.
  final List<Object?> endpointAuthorizations = [];

  /// How many refreshes reached the token endpoint.
  int refreshes = 0;

  String _valid = 'access-1';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    if (options.path == '/oauth/token') {
      endpointAuthorizations.add(options.headers['Authorization']);
      final body = await requestStream?.toList() ?? const <Uint8List>[];
      return _issue(utf8.decode(body.expand((chunk) => chunk).toList()));
    }
    final isAccepted = options.headers['Authorization'] == 'Bearer $_valid';
    return _json(isAccepted ? 200 : 401, isAccepted ? {'me': 'ada'} : {});
  }

  ResponseBody _issue(String request) {
    if (request.contains('refresh_token')) {
      refreshes++;
      _valid = 'access-${refreshes + 1}';
    }
    return _json(200, {
      'access_token': _valid,
      'refresh_token': 'refresh-${refreshes + 1}',
      'expires_in': lifetime,
    });
  }

  ResponseBody _json(int status, Map<String, Object?> body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> main() async {
  final server = StandInServer(lifetime: 5);
  final clients = SessionClients(
    baseUrl: 'https://api.example.com',
    store: InMemoryTokenStore<TokenSet>(),
    adapter: server,
  );

  await clients.signIn('ada@example.com', 'correct horse');
  final response = await clients.api.get<Object?>('/me');

  stdout.writeln(
    '${response.statusCode} after ${server.refreshes} refresh; '
    'requests: ${server.paths}',
  );
  await clients.dispose();
}
