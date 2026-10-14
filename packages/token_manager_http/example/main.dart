import 'dart:io';

import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

final class _ExampleRefresher implements TokenRefresher<TokenSet> {
  const _ExampleRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    // Call your token endpoint here. Throw InvalidGrant when the refresh
    // token was rejected for good, and Transient when a retry may succeed.
    return const TokenSet(accessToken: 'fresh');
  }
}

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(const TokenSet(accessToken: 'stale')),
    refresher: const _ExampleRefresher(),
  );

  // Stands in for the network: it answers 401 to every token but `fresh`.
  // In an app the inner client is `Client()`.
  final server = MockClient((request) async {
    if (request.headers['authorization'] != 'Bearer fresh') {
      return Response('expired', 401);
    }
    return Response('{"me":"ada"}', 200);
  });

  final client = HttpTokenClient<TokenSet>(manager: manager, inner: server);
  final response = await client.get(Uri.parse('https://api.example.com/me'));
  stdout.writeln(
    'Status ${response.statusCode} after one refresh and replay: '
    '${response.body}',
  );

  client.close();
  await manager.dispose();
}
