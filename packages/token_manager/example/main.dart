import 'dart:io';

import 'package:token_manager/token_manager.dart';

final class _ExampleRefresher implements TokenRefresher<TokenSet> {
  const _ExampleRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    return TokenSet(
      accessToken: 'new-access-token',
      refreshToken: 'new-refresh-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: const _ExampleRefresher(),
    info: const TokenSetInfo(),
  );

  // These tokens expire inside the default 30 second skew, so the next call
  // to validToken() refreshes them.
  await manager.setTokens(
    TokenSet(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().add(const Duration(seconds: 10)),
    ),
  );

  final tokens = await manager.validToken();
  stdout.writeln('Using access token: ${tokens.accessToken}');

  await manager.dispose();
}
