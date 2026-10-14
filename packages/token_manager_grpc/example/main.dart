import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

final class _ExampleRefresher implements TokenRefresher<TokenSet> {
  const _ExampleRefresher();

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    // Exchange current.refreshToken with your auth server here.
    return TokenSet(
      accessToken: 'new-access-token',
      refreshToken: 'new-refresh-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

final class _BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  const _BearerDelegate();

  @override
  grpc.CallOptions buildCallOptions(TokenSet? tokens) => grpc.CallOptions(
    metadata: {
      if (tokens != null) 'authorization': 'Bearer ${tokens.accessToken}',
    },
  );
}

Future<void> main() async {
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: const _ExampleRefresher(),
    info: const TokenSetInfo(),
  );
  await manager.setTokens(
    TokenSet(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );

  final channel = grpc.ClientChannel(
    'localhost',
    port: 50051,
    options: const grpc.ChannelOptions(
      credentials: grpc.ChannelCredentials.insecure(),
    ),
  );
  // Pass the same interceptors to your generated client, for example
  // `GreeterClient(channel, interceptors: [interceptor])`. Every call then
  // carries a valid token and is replayed once after UNAUTHENTICATED.
  final client = grpc.Client(
    channel,
    interceptors: [
      GrpcTokenInterceptor<TokenSet>(
        manager: manager,
        delegate: const _BearerDelegate(),
      ),
    ],
  );
  stdout.writeln('Client ready: ${client.runtimeType}');

  await channel.shutdown();
  await manager.dispose();
}
