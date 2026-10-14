import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/not_authenticated.dart';
import 'package:token_manager/src/refresh_failure.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';

void main() {
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test(
    'a refresh in flight does not serve a session started after it',
    () async {
      final engine = fixture.engine();
      await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
      final stale = engine.validToken();
      await settle();
      await engine.logout();
      final second = fixture.tokens(const Duration(seconds: 10), access: 'b');
      await engine.setTokens(second);
      final fresh = fixture.tokens(const Duration(hours: 1), access: 'c');

      final next = engine.validToken();
      await settle();
      expect(fixture.refresher.callCount, 2);
      expect(fixture.refresher.requested.last, same(second));
      fixture.refresher.complete(fresh, call: 1);
      fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));

      expect(await next, same(fresh));
      expect(await stale, same(fresh));
    },
  );

  test(
    'a token rejected after setTokens mid-flight starts a new refresh',
    () async {
      final engine = fixture.engine();
      await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
      final first = engine.validToken();
      await settle();
      final replaced = fixture.tokens(const Duration(hours: 1), access: 'b');
      await engine.setTokens(replaced);
      final fresh = fixture.tokens(const Duration(hours: 1), access: 'c');

      final next = engine.validToken(rejected: replaced);
      await settle();
      expect(fixture.refresher.callCount, 2);
      fixture.refresher.complete(fresh, call: 1);
      fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));

      expect(await next, same(fresh));
      expect(await first, same(fresh));
    },
  );

  test(
    'InvalidGrant after setTokens mid-flight serves the new tokens',
    () async {
      final engine = fixture.engine();
      await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
      final pending = engine.validToken();
      await settle();
      final replaced = fixture.tokens(const Duration(hours: 1), access: 'b');
      await engine.setTokens(replaced);

      fixture.refresher.fail(const InvalidGrant());

      expect(await pending, same(replaced));
      expect(fixture.store.stored, same(replaced));
      expect(fixture.store.deletes, 0);
      expect(engine.state.tokensOrNull, same(replaced));
    },
  );

  test('InvalidGrant after logout mid-flight is NotAuthenticated', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
    final pending = expectLater(
      engine.validToken(),
      throwsA(isA<NotAuthenticated>()),
    );
    await settle();
    await engine.logout();

    fixture.refresher.fail(const InvalidGrant());
    await pending;

    expect(fixture.store.deletes, 1);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test(
    'InvalidGrant still reaches waiters when the store cannot delete',
    () async {
      final engine = fixture.engine();
      await engine.setTokens(fixture.tokens(const Duration(seconds: 10)));
      final failed = expectLater(
        engine.validToken(),
        throwsA(isA<InvalidGrant>()),
      );
      await settle();
      fixture.store.deleteError = Exception('locked');

      fixture.refresher.fail(const InvalidGrant());
      await failed;

      expect(engine.state, isA<Unauthenticated<TokenSet>>());
    },
  );

  test(
    'an Error from the refresher does not leave the state Refreshing',
    () async {
      final engine = fixture.engine();
      final old = fixture.tokens(const Duration(seconds: 10));
      await engine.setTokens(old);
      final failed = expectLater(
        engine.validToken(),
        throwsA(isA<StateError>()),
      );
      await settle();

      fixture.refresher.fail(StateError('boom'));
      await failed;

      expect(engine.state.tokensOrNull, same(old));
      expect(engine.state, isA<Authenticated<TokenSet>>());
    },
  );
}
