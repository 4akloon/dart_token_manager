import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

/// Writes the access token into the `Authorization` header.
final class BearerDelegate extends RefreshInterceptorDelegate<TokenSet> {
  /// Creates the delegate.
  const BearerDelegate();

  @override
  void applyTo(RequestOptions options, TokenSet tokens) {
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
  }
}

/// A [Dio] for your API that attaches tokens, refreshes once for any number
/// of parallel 401s and replays each rejected request once.
final class ApiClient {
  /// Creates the client; [adapter] replaces the network in tests.
  ApiClient({
    required TokenManager<TokenSet> manager,
    required String baseUrl,
    HttpClientAdapter? adapter,
  }) : dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
    }
    dio.interceptors.add(
      DioTokenInterceptor<TokenSet>(
        manager: manager,
        delegate: const BearerDelegate(),
        // The Dio the interceptor is added to: the replay keeps its adapter,
        // its other interceptors and its timeouts.
        dio: dio,
      ),
    );
  }

  /// The client to use for every authorized call.
  final Dio dio;
}

// ---- Stand-ins for the network and the token endpoint, so this file runs
// ---- without either.

/// A refresher that counts its calls and issues `fresh` tokens.
final class StandInRefresher implements TokenRefresher<TokenSet> {
  /// How many times [refresh] was called.
  int calls = 0;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    calls++;
    return const TokenSet(accessToken: 'fresh', refreshToken: 'refresh-2');
  }
}

/// A server that answers 401 to every access token but `fresh`.
final class StandInServer implements HttpClientAdapter {
  /// The `Authorization` header of every request, in arrival order.
  final List<String?> received = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final authorization = options.headers['Authorization'];
    received.add(authorization is String ? authorization : null);
    final isAccepted = authorization == 'Bearer fresh';
    return ResponseBody.fromString(
      isAccepted ? jsonEncode({'me': 'ada'}) : '',
      isAccepted ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> main() async {
  final refresher = StandInRefresher();
  final server = StandInServer();
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(
      const TokenSet(accessToken: 'stale', refreshToken: 'refresh-1'),
    ),
    refresher: refresher,
  );
  final api = ApiClient(
    manager: manager,
    baseUrl: 'https://api.example.com',
    adapter: server,
  );

  final responses = await Future.wait([
    api.dio.get<Object?>('/me'),
    api.dio.get<Object?>('/me'),
    api.dio.get<Object?>('/me'),
  ]);

  stdout.writeln(
    '${responses.length} responses, ${refresher.calls} refresh, '
    '${server.received.length} requests sent',
  );
  await manager.dispose();
}
