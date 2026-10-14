import 'dart:io';

import 'package:gql/language.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

final class _ExampleRefresher implements TokenRefresher<TokenSet> {
  const _ExampleRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async =>
      const TokenSet(accessToken: 'fresh');
}

/// Stands in for `HttpLink`: it answers HTTP 401 to every token but `fresh`.
final class _FakeServer extends Link {
  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final headers = request.context.entry<HttpLinkHeaders>()?.headers;
    if (headers?['Authorization'] != 'Bearer fresh') {
      return Stream.error(const ServerException(statusCode: 401));
    }
    return Stream.value(const Response(data: {'me': 'ada'}, response: {}));
  }
}

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(const TokenSet(accessToken: 'stale')),
    refresher: const _ExampleRefresher(),
  );

  // In an app the chain is
  // Link.from([DedupeLink(), TokenManagerLink(...), HttpLink(uri)]).
  final link = Link.from([
    TokenManagerLink<TokenSet>(
      manager: manager,
      headers: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
    ),
    _FakeServer(),
  ]);

  final request = Request(
    operation: Operation(document: parseString('query Me { me }')),
  );
  final response = await link.request(request).first;
  stdout.writeln('Data after one refresh and replay: ${response.data}');

  await manager.dispose();
}
