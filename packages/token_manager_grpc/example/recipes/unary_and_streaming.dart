import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_grpc/token_manager_grpc.dart';

/// Exchanges a refresh token for new tokens; implement it with a client of
/// your auth service that has no token interceptor.
abstract interface class TokenExchange {
  /// Returns the tokens issued for [refreshToken].
  Future<TokenSet> exchange(String refreshToken);
}

/// Sends the access token as `authorization: Bearer <token>` metadata.
final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  /// Creates the delegate.
  const BearerDelegate();

  @override
  grpc.CallOptions buildCallOptions(TokenSet? tokens) => grpc.CallOptions(
    metadata: {
      if (tokens != null) 'authorization': 'Bearer ${tokens.accessToken}',
    },
  );
}

/// Refreshes through [TokenExchange].
final class ExchangeRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher over [_exchange].
  const ExchangeRefresher(this._exchange);

  final TokenExchange _exchange;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    final refreshToken = current.refreshToken;
    if (refreshToken == null) {
      throw const InvalidGrant();
    }
    try {
      return await _exchange.exchange(refreshToken);
    } on grpc.GrpcError catch (error) {
      if (error.code == grpc.StatusCode.unauthenticated) {
        // The auth service rejected the refresh token for good.
        throw const InvalidGrant();
      }
      rethrow; // anything else, such as UNAVAILABLE, is Transient
    }
  }
}

/// One channel, one manager and the interceptor that joins them.
final class GrpcSession {
  /// Creates a session; [store] defaults to memory.
  factory GrpcSession({
    required grpc.ClientChannel channel,
    required TokenExchange exchange,
    TokenStore<TokenSet>? store,
  }) {
    final manager = TokenManager<TokenSet>.create(
      store: store ?? InMemoryTokenStore<TokenSet>(),
      refresher: ExchangeRefresher(exchange),
      info: const TokenSetInfo(),
    );
    final interceptor = GrpcTokenInterceptor<TokenSet>(
      manager: manager,
      delegate: const BearerDelegate(),
    );
    return GrpcSession._(channel, manager, interceptor);
  }

  const GrpcSession._(this.channel, this.manager, this.interceptor);

  /// The channel every client of the app shares.
  final grpc.ClientChannel channel;

  /// The manager behind [interceptor]; call `setTokens` after sign-in.
  final TokenManager<TokenSet> manager;

  /// Pass it to every generated client, for example
  /// `GreeterClient(channel, interceptors: [session.interceptor])`.
  ///
  /// Unary calls are replayed once after UNAUTHENTICATED. A streaming call is
  /// reopened once, only before its first response and only when its request
  /// stream ended after at most one request.
  final GrpcTokenInterceptor<TokenSet> interceptor;

  /// Shuts the channel down and releases the manager.
  Future<void> close() async {
    await channel.shutdown();
    await manager.dispose();
  }
}

// ---- Stand-in for your auth service, so this file runs without a server.

/// An auth service that issues `access-<n>` on its n-th exchange.
final class StandInExchange implements TokenExchange {
  /// How many exchanges reached the service.
  int calls = 0;

  @override
  Future<TokenSet> exchange(String refreshToken) async {
    calls++;
    return TokenSet(accessToken: 'access-$calls', refreshToken: 'refresh');
  }
}

Future<void> main() async {
  final session = GrpcSession(
    channel: grpc.ClientChannel(
      'localhost',
      port: 50051,
      options: const grpc.ChannelOptions(
        credentials: grpc.ChannelCredentials.insecure(),
      ),
    ),
    exchange: StandInExchange(),
  );
  await session.manager.setTokens(
    const TokenSet(accessToken: 'access-0', refreshToken: 'refresh'),
  );

  // Nothing connects until the first call.
  final client = grpc.Client(
    session.channel,
    interceptors: [session.interceptor],
  );
  stdout.writeln('Client ready: ${client.runtimeType}');

  await session.close();
}
