import 'dart:io';

import 'package:token_manager/token_manager.dart';

/// The endpoint your repository calls; implement it with your HTTP client.
abstract interface class ProfileApi {
  /// Returns the profile, or throws [UnauthorizedException] on a 401.
  Future<String> fetchProfile(String accessToken);
}

/// The server rejected the access token.
final class UnauthorizedException implements Exception {
  /// Creates the exception.
  const UnauthorizedException();
}

/// The code under test: it asks the manager for valid tokens on every call.
final class ProfileRepository {
  /// Creates a repository over [_manager] and [_api].
  const ProfileRepository(this._manager, this._api);

  final TokenManager<TokenSet> _manager;
  final ProfileApi _api;

  /// Loads the profile, refreshing the tokens first when they are about to
  /// expire and replaying the call once when the server rejects them.
  Future<String> load() {
    return _manager.authorize(
      (tokens) => _api.fetchProfile(tokens.accessToken),
      isAuthFailure: (error) => error is UnauthorizedException,
    );
  }
}

// ---- Test doubles; none of them touches the network.

/// A clock that only moves when the test says so.
final class FixedClock implements Clock {
  /// Creates a clock reading [current].
  FixedClock(this.current);

  /// The time the clock reads.
  DateTime current;

  @override
  DateTime now() => current;
}

/// A refresher that counts its calls, or fails with [failure].
final class CountingRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher that succeeds unless [failure] is set.
  CountingRefresher({this.failure});

  /// What every call throws; `null` makes calls succeed.
  final RefreshFailure? failure;

  /// How many times [refresh] was called.
  int calls = 0;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    calls++;
    final error = failure;
    if (error != null) {
      throw error;
    }
    return TokenSet(
      accessToken: 'fresh-$calls',
      refreshToken: 'refresh-$calls',
      expiresAt: DateTime.utc(2030),
    );
  }
}

/// A server that accepts only the access tokens in [accepted].
final class FakeProfileApi implements ProfileApi {
  /// Creates a server for [accepted] access tokens.
  FakeProfileApi(this.accepted);

  /// The access tokens the server answers 200 to.
  final Set<String> accepted;

  /// Every access token the server received, in order.
  final List<String> seen = [];

  @override
  Future<String> fetchProfile(String accessToken) async {
    seen.add(accessToken);
    if (!accepted.contains(accessToken)) {
      throw const UnauthorizedException();
    }
    return 'profile of ada';
  }
}

Future<void> main() async {
  final clock = FixedClock(DateTime.utc(2026));
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: CountingRefresher(),
    info: const TokenSetInfo(),
    clock: clock,
  );
  await manager.setTokens(
    TokenSet(
      accessToken: 'stale',
      refreshToken: 'refresh',
      expiresAt: clock.current.add(const Duration(seconds: 10)),
    ),
  );

  final api = FakeProfileApi({'fresh-1'});
  final profile = await ProfileRepository(manager, api).load();
  stdout.writeln('$profile after sending ${api.seen}');

  await manager.dispose();
}
