# Recipe: GraphQL queries and WebSocket subscriptions

Authorize queries and mutations over HTTP with `TokenManagerLink`, and
subscriptions over a WebSocket with `TokenManagerSocketAuth`, from one manager.

## The code

`AuthorizedLinks` builds the manager and the combined `Link` for your client.
`httpLink` is your terminating link (for example `HttpLink(url)`). `buildSocket`
creates the WebSocket link of your client; in an app it passes
`initialPayload` and `onConnectionLost` to that client's socket config, as the
[subscriptions guide](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_gql/doc/subscriptions.md)
shows. The recipe depends only on `gql_link`, so it does not import a client. It parses documents with `parseString` from `package:gql`; add `gql` to your own
dependencies to do the same.
`StandInServer` replaces your server.

<!-- include: example/recipes/queries_and_subscriptions.dart -->
```dart
import 'dart:async';
import 'dart:io';

import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

/// Builds the WebSocket link of your GraphQL client from the two callbacks of
/// [TokenManagerSocketAuth].
///
/// In an app this is where you create your client's WebSocket link, passing
/// [initialPayload] and [onConnectionLost] to its config.
typedef SocketLinkBuilder =
    Link Function({
      required Future<Map<String, Object?>> Function() initialPayload,
      required Future<Duration?> Function(int? code, String? reason)
      onConnectionLost,
    });

/// Refreshes with a mutation sent through [_link], the HTTP link alone.
///
/// The link must not contain a [TokenManagerLink].
final class MutationRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher that sends the refresh mutation through [_link].
  const MutationRefresher(this._link);

  final Link _link;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    final response = await _link
        .request(
          Request(
            operation: Operation(
              document: parseString(
                r'mutation Refresh($token: String!) { '
                r'refresh(refreshToken: $token) '
                '{ accessToken refreshToken } }',
              ),
              operationName: 'Refresh',
            ),
            variables: {'token': current.refreshToken},
          ),
        )
        .first;
    return const TokenPayload().parse(response.data, 'refresh');
  }
}

/// Reads the tokens a login or refresh mutation returns.
final class TokenPayload {
  /// Creates the reader.
  const TokenPayload();

  /// Returns the tokens under `data[field]`, or throws a [FormatException]
  /// (a rejected login arrives as GraphQL `errors` and has no `data`).
  TokenSet parse(Map<String, Object?>? data, String field) {
    return switch (data?[field]) {
      {
        'accessToken': final String access,
        'refreshToken': final String refresh,
      } =>
        TokenSet(
          accessToken: access,
          refreshToken: refresh,
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        ),
      _ => throw FormatException('No tokens in the "$field" answer'),
    };
  }
}

/// The links of an app: queries and mutations over HTTP, subscriptions over a
/// WebSocket, one session.
final class AuthorizedLinks {
  /// Creates the links.
  ///
  /// [httpLink] is your terminating HTTP link, for example `HttpLink(url)`;
  /// [buildSocket] creates the WebSocket link of your client.
  factory AuthorizedLinks({
    required Link httpLink,
    required SocketLinkBuilder buildSocket,
    TokenStore<TokenSet>? store,
  }) {
    final manager = TokenManager<TokenSet>.create(
      store: store ?? InMemoryTokenStore<TokenSet>(),
      refresher: MutationRefresher(httpLink),
      info: const TokenSetInfo(),
    );
    final socketAuth = TokenManagerSocketAuth<TokenSet>(
      manager: manager,
      payload: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
    );
    final link = Link.split(
      (request) =>
          request.operation.getOperationType() == OperationType.subscription,
      buildSocket(
        initialPayload: socketAuth.initialPayload,
        onConnectionLost: socketAuth.onConnectionLost,
      ),
      Link.from([
        // Add DedupeLink() first, as in the README, when you use it.
        TokenManagerLink<TokenSet>(
          manager: manager,
          headers: (tokens) => {
            'Authorization': 'Bearer ${tokens.accessToken}',
          },
        ),
        httpLink,
      ]),
    );
    return AuthorizedLinks._(manager, link);
  }

  const AuthorizedLinks._(this.manager, this.link);

  /// The manager behind the links.
  final TokenManager<TokenSet> manager;

  /// The link to give to your GraphQL client.
  final Link link;

  /// Signs in with a mutation that is sent without tokens.
  Future<void> signIn(String email, String password) async {
    final request = Request(
      operation: Operation(
        document: parseString(
          r'mutation Login($email: String!, $password: String!) { '
          r'login(email: $email, password: $password) '
          '{ accessToken refreshToken } }',
        ),
        operationName: 'Login',
      ),
      variables: {'email': email, 'password': password},
      // A login runs before tokens exist; without this entry the link would
      // fail it with NotAuthenticated.
      context: const Context().withEntry(const SkipAuthorization()),
    );
    final response = await link.request(request).first;
    await manager.setTokens(const TokenPayload().parse(response.data, 'login'));
  }

  /// Releases the manager.
  Future<void> dispose() => manager.dispose();
}

// ---- Stand-in for your server, so this file runs without a network.

/// Answers `Login`, `Refresh`, `Me` and `Ticks` like a GraphQL server that
/// accepts only its newest access token.
final class StandInServer extends Link {
  /// How many `Refresh` mutations reached the server.
  int refreshes = 0;

  /// The `Authorization` header of every `Me` query, in arrival order.
  final List<String?> received = [];

  String _valid = 'access-1';

  /// Makes the access token in use stale, like an early revocation.
  void revokeAccessToken() => _valid = 'revoked';

  /// Whether the server rejects every `Me` query, whatever its token.
  bool rejectsEveryToken = false;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final headers = request.context.entry<HttpLinkHeaders>()?.headers;
    return switch (request.operation.operationName) {
      'Login' => _tokens('login'),
      'Refresh' => _refresh(),
      'Ticks' => Stream.value(const Response(data: {'tick': 1}, response: {})),
      _ => _me(headers?['Authorization']),
    };
  }

  Stream<Response> _refresh() {
    refreshes++;
    _valid = 'access-${refreshes + 1}';
    return _tokens('refresh');
  }

  Stream<Response> _tokens(String field) {
    return Stream.value(
      Response(
        data: {
          field: {
            'accessToken': _valid,
            'refreshToken': 'refresh-${refreshes + 1}',
          },
        },
        response: const {},
      ),
    );
  }

  Stream<Response> _me(String? authorization) {
    received.add(authorization);
    if (rejectsEveryToken || authorization != 'Bearer $_valid') {
      return Stream.error(const ServerException(statusCode: 401));
    }
    return Stream.value(const Response(data: {'me': 'ada'}, response: {}));
  }
}

Future<void> main() async {
  final server = StandInServer();
  final links = AuthorizedLinks(
    httpLink: server,
    buildSocket: ({required initialPayload, required onConnectionLost}) =>
        server,
  );

  await links.signIn('ada@example.com', 'correct horse');
  server.revokeAccessToken();
  final response = await links.link
      .request(
        Request(
          operation: Operation(
            document: parseString('query Me { me }'),
            operationName: 'Me',
          ),
        ),
      )
      .first;

  stdout.writeln(
    'Data ${response.data} after ${server.refreshes} refresh; '
    'sent ${server.received}',
  );
  await links.dispose();
}
```

Run it with `dart run example/recipes/queries_and_subscriptions.dart`. The test
`test/recipes/queries_and_subscriptions_test.dart` checks every behaviour under What you get.

## What you get

- `signIn` runs without tokens because its request carries
  `SkipAuthorization`.
- A query sent while signed out is not sent: it fails with a `LinkException`
  whose `originalException` is `NotAuthenticated`.
- A query the server rejects with HTTP 401 is refreshed once and replayed once;
  when the replay is rejected too, its error reaches the client. Other
  rejections the link recognises are listed in
  [Auth failures](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_gql/doc/auth_failures.md).
- A subscription goes to the socket link; the socket payload carries the
  current access token.
- A close with the auth code (4401 by default) refreshes the tokens once and
  asks the client to reconnect at once; any other close leaves them alone.

## Common mistakes

- **Putting `TokenManagerLink` after the terminating link.** It must come before
  it, after `DedupeLink` when you use one.
- **Combining it with the client's own auth link.** The client's
  own auth link sets the same header and cannot replay; use one of the two, as
  the [Clients guide](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_gql/doc/clients.md)
  explains.
- **Refreshing through the full link.** `MutationRefresher` sends its mutation
  through `httpLink` alone; give it a link that has no `TokenManagerLink`.
- **Logging in without `SkipAuthorization`.** A login runs before tokens exist;
  sent without the marker while signed out it fails like the query above.
- **Leaving the socket open after logout.** The app still has to close or
  dispose the WebSocket link when `states` emits `Unauthenticated`, and bound
  the reconnects after a refresh; see the subscriptions guide.
- **Using the wrong close code.** Only 4401 triggers a refresh by default; pass
  `authCloseCodes` to `TokenManagerSocketAuth` with what your server sends.

## See also

- [Getting started](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_gql/doc/getting_started.md)
- [Auth failures](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_gql/doc/auth_failures.md)
- [Clients](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager_gql/doc/clients.md)
