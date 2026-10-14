import 'package:dio/dio.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_dio/token_manager_dio.dart';

import 'bearer_delegate.dart';
import 'fake_http_adapter.dart';
import 'fake_refresher.dart';

/// A [Dio] with a [DioTokenInterceptor], a manager and fakes, wired together.
///
/// The session starts with the access token `old`. Unless `accepted` says
/// otherwise the server accepts only `Bearer new`, so every first attempt gets
/// a 401.
final class DioFixture {
  /// Creates a fixture.
  ///
  /// [signedIn] false starts without tokens, [withRefresher] false builds a
  /// manager that cannot refresh, [refreshFailure] makes refreshes fail,
  /// [accepted] is the one `Authorization` value the server answers 200 to,
  /// [ownDio] false lets the replay go through a separate `Dio`, and
  /// [delegate] replaces the bearer delegate.
  factory DioFixture({
    bool signedIn = true,
    bool withRefresher = true,
    RefreshFailure? refreshFailure,
    bool ownDio = true,
    String accepted = 'Bearer new',
    RefreshInterceptorDelegate<TokenSet> delegate = const BearerDelegate(),
  }) {
    final adapter = FakeHttpAdapter(accepted: accepted);
    final refresher = FakeRefresher(failure: refreshFailure);
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(signedIn ? initial : null),
      refresher: withRefresher ? refresher : null,
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter;
    final replayDio = ownDio ? dio : (Dio()..httpClientAdapter = adapter);
    dio.interceptors.add(
      DioTokenInterceptor<TokenSet>(
        manager: manager,
        delegate: delegate,
        dio: replayDio,
      ),
    );
    return DioFixture._(
      adapter: adapter,
      refresher: refresher,
      manager: manager,
      dio: dio,
      replayDio: replayDio,
    );
  }

  DioFixture._({
    required this.adapter,
    required this.refresher,
    required this.manager,
    required this.dio,
    required this.replayDio,
  });

  /// The tokens the session starts with.
  static const TokenSet initial = TokenSet(
    accessToken: 'old',
    refreshToken: 'refresh-1',
  );

  /// The server stand-in.
  final FakeHttpAdapter adapter;

  /// The refresher the manager uses.
  final FakeRefresher refresher;

  /// The manager the interceptor asks for tokens.
  final TokenManager<TokenSet> manager;

  /// The client under test.
  final Dio dio;

  /// The client that sends replays; [dio] itself unless `ownDio` was false.
  final Dio replayDio;
}
