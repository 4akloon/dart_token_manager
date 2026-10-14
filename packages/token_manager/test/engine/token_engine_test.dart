import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/not_authenticated.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';

void main() {
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  test(
    'starts unauthenticated and replays the state to late listeners',
    () async {
      final engine = fixture.engine();

      expect(engine.state, isA<Unauthenticated<TokenSet>>());
      await expectLater(
        engine.states,
        emits(isA<Unauthenticated<TokenSet>>()),
      );
    },
  );

  test('current loads the stored tokens once', () async {
    final stored = fixture.tokens(const Duration(hours: 1));
    fixture.store.stored = stored;
    final engine = fixture.engine();

    expect(await engine.current(), same(stored));
    expect(await engine.current(), same(stored));

    expect(fixture.store.reads, 1);
    expect(engine.state, isA<Authenticated<TokenSet>>());
  });

  test('current is null when nothing is stored', () async {
    expect(await fixture.engine().current(), isNull);
  });

  test('a failed read is retried on the next call', () async {
    final stored = fixture.tokens(const Duration(hours: 1));
    fixture.store
      ..stored = stored
      ..readError = Exception('disk');
    final engine = fixture.engine();

    await expectLater(engine.current(), throwsException);
    fixture.store.readError = null;

    expect(await engine.current(), same(stored));
    expect(fixture.store.reads, 2);
  });

  test('setTokens persists the tokens and emits Authenticated', () async {
    final engine = fixture.engine();
    final tokens = fixture.tokens(const Duration(hours: 1));

    await engine.setTokens(tokens);

    expect(fixture.store.stored, same(tokens));
    expect(engine.state.tokensOrNull, same(tokens));
  });

  test('setTokens does not emit when the store fails', () async {
    fixture.store.writeError = Exception('full');
    final engine = fixture.engine();

    await expectLater(
      engine.setTokens(fixture.tokens(const Duration(hours: 1))),
      throwsException,
    );

    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('logout deletes the tokens and emits Unauthenticated', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(hours: 1)));

    await engine.logout();

    expect(fixture.store.stored, isNull);
    expect(engine.state, isA<Unauthenticated<TokenSet>>());
  });

  test('validToken throws NotAuthenticated without tokens', () async {
    await expectLater(
      fixture.engine().validToken(),
      throwsA(isA<NotAuthenticated>()),
    );
  });

  test('validToken returns the stored tokens while they are valid', () async {
    final stored = fixture.tokens(const Duration(hours: 1));
    fixture.store.stored = stored;

    expect(await fixture.engine().validToken(), same(stored));
    expect(fixture.refresher.callCount, 0);
  });

  test('dispose completes the states stream', () async {
    final engine = fixture.engine();

    await engine.dispose();

    await expectLater(
      engine.states,
      emitsInOrder([isA<Unauthenticated<TokenSet>>(), emitsDone]),
    );
  });
}
