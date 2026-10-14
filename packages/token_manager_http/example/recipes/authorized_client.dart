import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

/// Reads the answer of the token endpoint.
final class TokenEndpointAnswer {
  /// Creates the reader.
  const TokenEndpointAnswer();

  /// Returns the tokens in [body], or throws a [FormatException].
  TokenSet parse(String body) {
    return switch (jsonDecode(body)) {
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

/// Refreshes with a plain [Client], which never asks the manager for tokens.
final class HttpRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher that posts to [endpoint] with [client].
  const HttpRefresher({required Client client, required Uri endpoint})
    : _client = client,
      _endpoint = endpoint;

  final Client _client;
  final Uri _endpoint;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    final response = await _client.post(
      _endpoint,
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': current.refreshToken ?? '',
      },
    );
    return switch (response.statusCode) {
      200 => const TokenEndpointAnswer().parse(response.body),
      // The server rejected the refresh token for good.
      400 => throw const InvalidGrant(),
      // Anything else may go away: the session stays.
      final int status => throw Transient(status),
    };
  }
}

/// An authorized [Client] and the manager behind it.
final class AuthorizedHttp {
  /// Creates the client over [transport]; [store] defaults to memory.
  factory AuthorizedHttp({
    required Client transport,
    required Uri origin,
    TokenStore<TokenSet>? store,
  }) {
    final tokenUri = origin.resolve(_tokenPath);
    final manager = TokenManager<TokenSet>.create(
      store: store ?? InMemoryTokenStore<TokenSet>(),
      refresher: HttpRefresher(client: transport, endpoint: tokenUri),
      info: const TokenSetInfo(),
    );
    final client = HttpTokenClient<TokenSet>(
      manager: manager,
      inner: transport,
      // The sign-in runs before tokens exist, so it must not ask for them.
      // The refresh never reaches this client: HttpRefresher uses the plain
      // transport.
      shouldAuthorize: (request) => request.url.path != _tokenPath,
    );
    return AuthorizedHttp._(manager, client, tokenUri);
  }

  const AuthorizedHttp._(this.manager, this.client, this._tokenUri);

  static const String _tokenPath = '/oauth/token';

  /// The manager behind [client].
  final TokenManager<TokenSet> manager;

  /// The client to use for every call to your API.
  final Client client;

  final Uri _tokenUri;

  /// Signs in and stores the tokens.
  Future<void> signIn(String email, String password) async {
    final response = await client.post(
      _tokenUri,
      body: {
        'grant_type': 'password',
        'username': email,
        'password': password,
      },
    );
    await manager.setTokens(
      const TokenEndpointAnswer().parse(response.body),
    );
  }

  /// Closes the client and releases the manager.
  Future<void> dispose() async {
    client.close();
    await manager.dispose();
  }
}

// ---- Stand-in for your server, so this file runs without a network.

/// Serves `/oauth/token` and `/me`; access tokens live [lifetime] seconds.
final class StandInServer {
  /// Creates a server that issues tokens valid for [lifetime] seconds.
  StandInServer({this.lifetime = 3600});

  /// The `expires_in` of an issued access token.
  final int lifetime;

  /// How many refreshes reached the token endpoint.
  int refreshes = 0;

  /// The `Authorization` header of every request to `/me`.
  final List<String?> received = [];

  /// The `Authorization` header of every request to `/oauth/token`.
  final List<String?> tokenEndpointHeaders = [];

  String _valid = 'access-1';

  /// The transport to pass to [AuthorizedHttp].
  Client get client => MockClient(_handle);

  /// Makes the access token in use stale, like an early revocation.
  void revokeAccessToken() => _valid = 'revoked';

  Future<Response> _handle(Request request) async {
    final authorization = request.headers['authorization'];
    if (request.url.path == '/oauth/token') {
      tokenEndpointHeaders.add(authorization);
      return _issue(request.bodyFields);
    }
    received.add(authorization);
    if (authorization != 'Bearer $_valid') {
      return Response('expired', 401);
    }
    return Response(jsonEncode({'me': 'ada'}), 200);
  }

  Response _issue(Map<String, String> form) {
    if (form['grant_type'] == 'refresh_token') {
      refreshes++;
      _valid = 'access-${refreshes + 1}';
    }
    return Response(
      jsonEncode({
        'access_token': _valid,
        'refresh_token': 'refresh-${refreshes + 1}',
        'expires_in': lifetime,
      }),
      200,
    );
  }
}

Future<void> main() async {
  final server = StandInServer();
  final http = AuthorizedHttp(
    transport: server.client,
    origin: Uri.parse('https://api.example.com'),
  );

  await http.signIn('ada@example.com', 'correct horse');
  server.revokeAccessToken();
  final response = await http.client.get(
    Uri.parse('https://api.example.com/me'),
  );

  stdout.writeln(
    '${response.statusCode} after ${server.refreshes} refresh: '
    '${response.body}',
  );
  await http.dispose();
}
