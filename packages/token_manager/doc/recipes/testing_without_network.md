# Recipe: test code that uses tokens without a network

Test a repository that calls `TokenManager.authorize` with a fake clock, a
counting refresher and a fake server. Nothing here touches the network and no
test waits for real time.

## The code

`ProfileRepository` is the code under test. `FixedClock`, `CountingRefresher`
and `FakeProfileApi` are the doubles; copy them next to your tests.

<!-- include: example/recipes/testing_without_network.dart -->
```dart
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
```

## The tests

<!-- include: test/recipes/testing_without_network_test.dart -->
```dart
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/testing_without_network.dart';

void main() {
  // Assigned in setUp, which runs before every test.
  late FixedClock clock;

  TokenManager<TokenSet> managerFor(
    CountingRefresher refresher,
    Duration life,
  ) {
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(
        TokenSet(
          accessToken: 'stale',
          refreshToken: 'refresh',
          expiresAt: clock.current.add(life),
        ),
      ),
      refresher: refresher,
      info: const TokenSetInfo(),
      clock: clock,
    );
    addTearDown(manager.dispose);
    return manager;
  }

  setUp(() => clock = FixedClock(DateTime.utc(2026)));

  test('tokens inside the skew are refreshed before the call', () async {
    final refresher = CountingRefresher();
    final api = FakeProfileApi({'fresh-1'});
    final repository = ProfileRepository(
      managerFor(refresher, const Duration(seconds: 10)),
      api,
    );

    await repository.load();

    expect(api.seen, ['fresh-1']);
    expect(refresher.calls, 1);
  });

  test('valid tokens are sent without a refresh', () async {
    final refresher = CountingRefresher();
    final api = FakeProfileApi({'stale'});
    final repository = ProfileRepository(
      managerFor(refresher, const Duration(hours: 1)),
      api,
    );

    await repository.load();

    expect(api.seen, ['stale']);
    expect(refresher.calls, 0);
  });

  test('a rejected token is refreshed and the call replayed once', () async {
    final refresher = CountingRefresher();
    final api = FakeProfileApi({'fresh-1'});
    final repository = ProfileRepository(
      managerFor(refresher, const Duration(hours: 1)),
      api,
    );

    await repository.load();

    expect(api.seen, ['stale', 'fresh-1']);
    expect(refresher.calls, 1);
  });

  test('a dead refresh token fails the call and signs out', () async {
    final manager = managerFor(
      CountingRefresher(failure: const InvalidGrant()),
      const Duration(hours: 1),
    );
    final repository = ProfileRepository(manager, FakeProfileApi({'fresh-1'}));

    await expectLater(repository.load(), throwsA(isA<InvalidGrant>()));

    expect(await manager.current(), isNull);
  });
}
```

In your project import your own repository instead of the recipe file.

## What you get

- Tokens inside the skew are refreshed before the call, by moving the clock
  or by creating them with a near expiry; valid tokens are sent as they are.
- A rejected token is refreshed once and the call replayed once.
- A dead refresh token fails the call with `InvalidGrant` and signs out.

## Common mistakes

- **Sleeping until a token expires.** Pass a `Clock` to `TokenManager.create`
  and move it.
- **Sharing one manager between tests.** Its state leaks; create one per test
  and dispose it, as `addTearDown(manager.dispose)` does.
- **Mocking `TokenManager`.** Use the real manager with an `InMemoryTokenStore`
  and a fake refresher; the refresh rules are what you want under test.
- **Asserting before the refresh finished.** Await the repository call first,
  then check the refresher.

## See also

- [Testing guide](https://github.com/4akloon/dart_token_manager/blob/main/packages/token_manager/doc/testing.md)
