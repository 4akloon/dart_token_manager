import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

import 'helpers/counting_refresher.dart';

void main() {
  TokenManagerSocketAuth<TokenSet> socketAuth(
    CountingRefresher refresher, {
    Set<int> authCloseCodes = const {4401},
  }) {
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(const TokenSet(accessToken: 'old')),
      refresher: refresher,
    );
    return TokenManagerSocketAuth<TokenSet>(
      manager: manager,
      payload: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
      authCloseCodes: authCloseCodes,
    );
  }

  test('initialPayload is built from valid tokens', () async {
    final auth = socketAuth(CountingRefresher());

    expect(await auth.initialPayload(), {'Authorization': 'Bearer old'});
  });

  test('an auth close code reconnects at once', () async {
    final auth = socketAuth(CountingRefresher());
    await auth.initialPayload();

    expect(await auth.onConnectionLost(4401, 'Unauthorized'), Duration.zero);
  });

  test('an auth close code refreshes the tokens once', () async {
    final refresher = CountingRefresher();
    final auth = socketAuth(refresher);
    await auth.initialPayload();

    await auth.onConnectionLost(4401, 'Unauthorized');

    expect(refresher.calls, 1);
  });

  test('the next initialPayload carries the refreshed tokens', () async {
    final auth = socketAuth(CountingRefresher());
    await auth.initialPayload();

    await auth.onConnectionLost(4401, 'Unauthorized');

    expect(await auth.initialPayload(), {'Authorization': 'Bearer fresh-1'});
  });

  test('another close code keeps the default delay', () async {
    final auth = socketAuth(CountingRefresher());
    await auth.initialPayload();

    expect(await auth.onConnectionLost(1006, null), isNull);
  });

  test('another close code refreshes nothing', () async {
    final refresher = CountingRefresher();
    final auth = socketAuth(refresher);
    await auth.initialPayload();

    await auth.onConnectionLost(1006, null);

    expect(refresher.calls, 0);
  });

  test('two auth closes in a row both reconnect at once', () async {
    final auth = socketAuth(CountingRefresher());
    await auth.initialPayload();

    await auth.onConnectionLost(4401, null);

    expect(await auth.onConnectionLost(4401, null), Duration.zero);
  });

  test('two auth closes in a row refresh once', () async {
    final refresher = CountingRefresher();
    final auth = socketAuth(refresher);
    await auth.initialPayload();

    await auth.onConnectionLost(4401, null);
    await auth.onConnectionLost(4401, null);

    expect(refresher.calls, 1);
  });

  test('a close before any connection keeps the default delay', () async {
    final auth = socketAuth(CountingRefresher());

    expect(await auth.onConnectionLost(4401, null), isNull);
  });

  test('a close before any connection refreshes nothing', () async {
    final refresher = CountingRefresher();
    final auth = socketAuth(refresher);

    await auth.onConnectionLost(4401, null);

    expect(refresher.calls, 0);
  });

  test('a code outside the configured auth close codes is ignored', () async {
    final auth = socketAuth(CountingRefresher(), authCloseCodes: {4001});
    await auth.initialPayload();

    expect(await auth.onConnectionLost(4401, null), isNull);
  });

  test('a configured auth close code refreshes the tokens', () async {
    final refresher = CountingRefresher();
    final auth = socketAuth(refresher, authCloseCodes: {4001});
    await auth.initialPayload();

    expect(await auth.onConnectionLost(4001, null), Duration.zero);
    expect(refresher.calls, 1);
  });

  test(
    'a failed refresh keeps the default delay instead of throwing',
    () async {
      final auth = socketAuth(CountingRefresher(failure: const InvalidGrant()));
      await auth.initialPayload();

      expect(await auth.onConnectionLost(4401, null), isNull);
    },
  );

  test(
    'initialPayload fails with NotAuthenticated once the session ended',
    () async {
      final auth = socketAuth(CountingRefresher(failure: const InvalidGrant()));
      await auth.initialPayload();
      await auth.onConnectionLost(4401, null);

      await expectLater(
        auth.initialPayload(),
        throwsA(isA<NotAuthenticated>()),
      );
    },
  );
}
