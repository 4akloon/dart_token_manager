import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import '../../example/recipes/login_and_set_tokens.dart'
    show GrantRejected, Session, StandInAuthServer;

void main() {
  // Assigned in setUp, which runs before every test.
  late StandInAuthServer server;
  late Session session;

  /// Replaces [server] and [session] with ones whose tokens live [lifetime].
  void sessionWith(Duration lifetime) {
    server = StandInAuthServer(lifetime: lifetime);
    session = Session(api: server);
    addTearDown(session.dispose);
  }

  setUp(() => sessionWith(const Duration(hours: 1)));

  test('signIn stores the tokens', () async {
    await session.signIn('ada@example.com', 'secret');

    final tokens = await session.manager.current();
    expect(tokens?.accessToken, 'access-1');
    expect(tokens?.expiresAt, isNotNull);
  });

  test('bad credentials leave the session signed out', () async {
    await expectLater(
      session.signIn('ada@example.com', 'wrong'),
      throwsA(isA<GrantRejected>()),
    );

    expect(await session.manager.current(), isNull);
  });

  test('signOut removes the tokens', () async {
    await session.signIn('ada@example.com', 'secret');

    await session.signOut();

    expect(await session.manager.current(), isNull);
  });

  test(
    'tokens inside the skew are refreshed once on the next validToken',
    () async {
      sessionWith(const Duration(seconds: 5));
      await session.signIn('ada@example.com', 'secret');

      final tokens = await session.manager.validToken();

      expect(tokens.accessToken, 'access-2');
      expect(server.refreshes, 1);
    },
  );

  test('a rejected refresh token signs the session out', () async {
    sessionWith(const Duration(seconds: 5));
    await session.signIn('ada@example.com', 'secret');
    server.isRevoked = true;

    await expectLater(
      session.manager.validToken(),
      throwsA(isA<InvalidGrant>()),
    );

    expect(await session.manager.current(), isNull);
  });

  test('a network error keeps the session', () async {
    sessionWith(const Duration(seconds: 5));
    await session.signIn('ada@example.com', 'secret');
    server.isOffline = true;

    await expectLater(
      session.manager.validToken(),
      throwsA(isA<Transient>()),
    );

    expect((await session.manager.current())?.accessToken, 'access-1');
  });

  test('concurrent validToken calls share one refresh', () async {
    sessionWith(const Duration(seconds: 5));
    await session.signIn('ada@example.com', 'secret');

    await Future.wait([
      for (var i = 0; i < 3; i++) session.manager.validToken(),
    ]);

    expect(server.refreshes, 1);
  });
}
