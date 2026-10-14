import 'dart:async';

import 'package:gql/language.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

import 'counting_refresher.dart';
import 'fake_terminal_link.dart';

/// Wires a [TokenManagerLink] between a [TokenManager] and a
/// [FakeTerminalLink], and builds requests and responses for it.
final class LinkFixture {
  /// Creates a fixture whose terminal answers with [outcomes]; the session
  /// holds the token `old` when [isSignedIn], and refreshes through
  /// [refresher] when [hasRefresher], which throws [refreshFailure] when it
  /// is set.
  factory LinkFixture({
    List<Object> outcomes = const [],
    bool isSignedIn = true,
    bool hasRefresher = true,
    Exception? refreshFailure,
  }) {
    final refresher = CountingRefresher(failure: refreshFailure);
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(
        isSignedIn ? const TokenSet(accessToken: 'old') : null,
      ),
      refresher: hasRefresher ? refresher : null,
    );
    return LinkFixture._(manager, refresher, FakeTerminalLink(outcomes));
  }

  LinkFixture._(this.manager, this.refresher, this.terminal)
    : link = Link.from([
        TokenManagerLink<TokenSet>(
          manager: manager,
          headers: (tokens) => {
            'Authorization': 'Bearer ${tokens.accessToken}',
          },
        ),
        terminal,
      ]);

  /// An HTTP 401 as `HttpLink` reports it.
  static const ServerException unauthorized = ServerException(statusCode: 401);

  /// An HTTP 403 as `HttpLink` reports it for a GraphQL JSON body: the
  /// parsed response carries `extensions.code` [code].
  static ServerException forbidden({String code = 'UNAUTHENTICATED'}) =>
      ServerException(statusCode: 403, parsedResponse: rejected(code: code));

  /// Matches a [LinkException] whose `originalException` is a [T].
  static Matcher wrapping<T>() => isA<LinkException>().having(
    (e) => e.originalException,
    'originalException',
    isA<T>(),
  );

  /// A successful response.
  static const Response ok = Response(data: {'me': 'ada'}, response: {});

  /// The session's manager.
  final TokenManager<TokenSet> manager;

  /// The manager's refresher.
  final CountingRefresher refresher;

  /// The link after the [TokenManagerLink].
  final FakeTerminalLink terminal;

  /// The chain under test: [TokenManagerLink] then [terminal].
  final Link link;

  /// A query request with [context].
  Request query({Context context = const Context()}) => Request(
    operation: Operation(document: parseString('query Me { me }')),
    context: context,
  );

  /// A response whose error has `extensions.code` [code] and whose data is
  /// [data].
  static Response rejected({
    String code = 'UNAUTHENTICATED',
    String message = 'not signed in',
    Map<String, Object?>? data,
  }) => Response(
    data: data,
    errors: [
      GraphQLError(message: message, extensions: {'code': code}),
    ],
    response: const {},
  );

  /// Sends [request] through [link] and collects every event and error until
  /// the stream ends.
  Future<List<Object>> send(Request request) {
    final events = <Object>[];
    final done = Completer<List<Object>>();
    link
        .request(request)
        .listen(
          events.add,
          onError: events.add,
          onDone: () => done.complete(events),
        );
    return done.future;
  }
}
