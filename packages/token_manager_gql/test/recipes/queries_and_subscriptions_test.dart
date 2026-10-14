import 'package:gql/language.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/queries_and_subscriptions.dart'
    show AuthorizedLinks, StandInServer;

void main() {
  // Assigned in setUp, which runs before every test.
  late StandInServer server;
  late AuthorizedLinks links;
  late Future<Map<String, Object?>> Function() payload;
  late Future<Duration?> Function(int? code, String? reason) connectionLost;
  late List<String> socketOperations;

  Request operation(String name, String document) => Request(
    operation: Operation(document: parseString(document), operationName: name),
  );

  Request query() => operation('Me', 'query Me { me }');

  setUp(() {
    server = StandInServer();
    socketOperations = [];
    links = AuthorizedLinks(
      httpLink: server,
      buildSocket: ({required initialPayload, required onConnectionLost}) {
        payload = initialPayload;
        connectionLost = onConnectionLost;
        return _RecordingLink(socketOperations);
      },
    );
  });

  tearDown(() => links.dispose());

  test('signIn works while signed out and stores the tokens', () async {
    await links.signIn('ada@example.com', 'secret');

    expect((await links.manager.current())?.accessToken, 'access-1');
  });

  test(
    'a query while signed out fails with a LinkException around NotAuthenticated',
    () async {
      await expectLater(
        links.link.request(query()).first,
        throwsA(
          isA<LinkException>().having(
            (error) => error.originalException,
            'originalException',
            isA<NotAuthenticated>(),
          ),
        ),
      );

      expect(server.received, isEmpty);
    },
  );

  test('a rejected query is refreshed and replayed once', () async {
    await links.signIn('ada@example.com', 'secret');
    server.revokeAccessToken();

    final response = await links.link.request(query()).first;

    expect(response.data, {'me': 'ada'});
    expect(server.refreshes, 1);
    expect(server.received, ['Bearer access-1', 'Bearer access-2']);
  });

  test(
    'a query rejected again after the replay is delivered as the error',
    () async {
      await links.signIn('ada@example.com', 'secret');
      server.rejectEveryToken();

      await expectLater(
        links.link.request(query()).first,
        throwsA(
          isA<ServerException>().having(
            (error) => error.statusCode,
            'statusCode',
            401,
          ),
        ),
      );

      expect(server.refreshes, 1);
      expect(server.received, hasLength(2));
    },
  );

  test('a subscription goes to the socket link, not the HTTP link', () async {
    await links.signIn('ada@example.com', 'secret');

    await links.link
        .request(operation('Ticks', 'subscription Ticks { tick }'))
        .first;

    expect(socketOperations, ['Ticks']);
    expect(server.received, isEmpty);
  });

  test('the socket payload carries the current access token', () async {
    await links.signIn('ada@example.com', 'secret');

    expect(await payload(), {'Authorization': 'Bearer access-1'});
  });

  test('an auth close code refreshes once and reconnects at once', () async {
    await links.signIn('ada@example.com', 'secret');
    await payload();

    final delay = await connectionLost(4401, 'Unauthorized');

    expect(delay, Duration.zero);
    expect(server.refreshes, 1);
    expect(await payload(), {'Authorization': 'Bearer access-2'});
  });

  test('another close code leaves the tokens alone', () async {
    await links.signIn('ada@example.com', 'secret');
    await payload();

    expect(await connectionLost(1006, null), isNull);
    expect(server.refreshes, 0);
  });
}

final class _RecordingLink extends Link {
  _RecordingLink(this._operations);

  final List<String> _operations;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final name = request.operation.operationName;
    if (name != null) {
      _operations.add(name);
    }
    return Stream.value(const Response(data: {'tick': 1}, response: {}));
  }
}
