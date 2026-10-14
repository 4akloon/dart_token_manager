import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

import '../../example/recipes/authorized_client.dart'
    show AuthorizedHttp, StandInServer;

/// A refresher the tests never reach.
final class _UnusedRefresher implements TokenRefresher<String> {
  const _UnusedRefresher();

  @override
  Future<String> refresh(String current) => throw UnimplementedError();
}

void main() {
  final me = Uri.parse('https://api.test/me');
  // Assigned in setUp, which runs before every test.
  late StandInServer server;
  late AuthorizedHttp http;

  setUp(() {
    server = StandInServer();
    http = AuthorizedHttp(
      transport: server.client,
      origin: Uri.parse('https://api.test'),
    );
  });

  tearDown(() => http.dispose());

  test('signIn stores the tokens without asking the manager for any', () async {
    await http.signIn('ada@example.com', 'secret');

    expect((await http.manager.current())?.accessToken, 'access-1');
  });

  test('the sign-in reaches the token endpoint without a token', () async {
    await http.signIn('ada@example.com', 'secret');

    expect(server.tokenEndpointHeaders, [null]);
  });

  test('a signed-in call carries the bearer header', () async {
    await http.signIn('ada@example.com', 'secret');

    final response = await http.client.get(me);

    expect(response.statusCode, 200);
    expect(server.received, ['Bearer access-1']);
  });

  test('a rejected token is refreshed and the call replayed once', () async {
    await http.signIn('ada@example.com', 'secret');
    server.revokeAccessToken();

    final response = await http.client.get(me);

    expect(response.statusCode, 200);
    expect(server.refreshes, 1);
    expect(server.received, ['Bearer access-1', 'Bearer access-2']);
  });

  test('parallel rejected calls share one refresh', () async {
    await http.signIn('ada@example.com', 'secret');
    server.revokeAccessToken();

    final responses = await Future.wait([
      http.client.get(me),
      http.client.get(me),
      http.client.get(me),
    ]);

    expect(responses.map((response) => response.statusCode), [200, 200, 200]);
    expect(server.refreshes, 1);
  });

  test('the refresh reaches the token endpoint without a token', () async {
    await http.signIn('ada@example.com', 'secret');
    server.revokeAccessToken();

    await http.client.get(me);

    expect(server.tokenEndpointHeaders, [null, null]);
  });

  test('a call while signed out fails with NotAuthenticated', () async {
    await expectLater(
      http.client.get(me),
      throwsA(isA<NotAuthenticated>()),
    );

    expect(server.received, isEmpty);
  });

  test('a call after close fails with ClientException', () async {
    await http.signIn('ada@example.com', 'secret');
    http.client.close();

    await expectLater(http.client.get(me), throwsA(isA<ClientException>()));
  });

  test('close leaves the manager open', () async {
    await http.signIn('ada@example.com', 'secret');

    http.client.close();

    expect((await http.manager.current())?.accessToken, 'access-1');
  });

  test('without shouldAuthorize a login while signed out fails with '
      'NotAuthenticated', () async {
    final unfiltered = HttpTokenClient<TokenSet>(
      manager: http.manager,
      inner: server.client,
    );

    await expectLater(
      unfiltered.post(Uri.parse('https://api.test/oauth/token')),
      throwsA(isA<NotAuthenticated>()),
    );

    expect(server.tokenEndpointHeaders, isEmpty);
  });

  test('a multipart request is sent once and its 401 is returned', () async {
    await http.signIn('ada@example.com', 'secret');
    server.revokeAccessToken();

    final streamed = await http.client.send(MultipartRequest('POST', me));

    expect(streamed.statusCode, 401);
    expect(server.received, ['Bearer access-1']);
  });

  test('a token type other than TokenSet without headers fails with '
      'ArgumentError', () async {
    final manager = TokenManager<String>.create(
      store: InMemoryTokenStore<String>(),
      refresher: const _UnusedRefresher(),
    );
    addTearDown(manager.dispose);

    expect(
      () => HttpTokenClient<String>(manager: manager, inner: server.client),
      throwsArgumentError,
    );
  });
}
