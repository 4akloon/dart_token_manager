import 'package:test/test.dart';
import 'package:token_manager/src/auth_state.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';

void main() {
  const ahead = Duration(minutes: 5);
  // Between the 30 second skew and the 5 minute window.
  const inWindow = Duration(minutes: 3);
  // Assigned in setUp, which runs before every test.
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('tokens with more than refreshAhead left are not refreshed', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(const Duration(minutes: 10));
    await engine.setTokens(current);

    expect(await engine.validToken(), same(current));
    await settle();

    expect(fixture.refresher.callCount, 0);
  });

  test('tokens inside the window are returned at once and refreshed', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    expect(await engine.validToken(), same(current));
    await settle();
    expect(fixture.refresher.callCount, 1);
    expect(engine.state, isA<Refreshing<TokenSet>>());
    fixture.refresher.complete(fresh);
    await settle();

    expect(engine.state, isA<Authenticated<TokenSet>>());
    expect(engine.state.tokensOrNull, same(fresh));
    expect(fixture.store.stored, same(fresh));
  });

  test('ten concurrent callers inside the window start one refresh', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);

    final results = await Future.wait([
      for (var i = 0; i < 10; i++) engine.validToken(),
    ]);
    await settle();

    expect(results, everyElement(same(current)));
    expect(fixture.refresher.callCount, 1);
  });

  test('a caller inside the skew joins the background refresh', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    await engine.validToken();
    fixture.clock.advance(const Duration(minutes: 2, seconds: 45));

    final blocked = engine.validToken();
    await settle();
    fixture.refresher.complete(fresh);

    expect(await blocked, same(fresh));
    expect(fixture.refresher.callCount, 1);
  });

  test('without refreshAhead the window changes nothing', () async {
    final engine = fixture.engine();
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);

    expect(await engine.validToken(), same(current));
    await settle();

    expect(fixture.refresher.callCount, 0);
  });

  test('tokens refreshed ahead can be refreshed ahead again later', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    await engine.setTokens(fixture.tokens(inWindow));
    await engine.validToken();
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    fixture.refresher.complete(fresh);
    await settle();

    fixture.clock.advance(const Duration(minutes: 56));
    await engine.validToken();
    await settle();

    expect(fixture.refresher.callCount, 2);
    expect(fixture.refresher.requested.last, same(fresh));
  });

  test(
    'a refresh that returns tokens still inside the window is not repeated',
    () async {
      final engine = fixture.engine(refreshAhead: ahead);
      await engine.setTokens(fixture.tokens(inWindow));
      await engine.validToken();
      final stillSoon = fixture.tokens(const Duration(minutes: 4), access: 'b');
      fixture.refresher.complete(stillSoon);
      await settle();

      expect(await engine.validToken(), same(stillSoon));
      expect(await engine.validToken(), same(stillSoon));
      await settle();

      expect(fixture.refresher.callCount, 1);
    },
  );

  test('tokens that never expire are not refreshed ahead', () async {
    final engine = fixture.engine(refreshAhead: ahead);
    const forever = TokenSet(accessToken: 'a');
    await engine.setTokens(forever);

    expect(await engine.validToken(), same(forever));
    await settle();

    expect(fixture.refresher.callCount, 0);
  });

  test('refreshAhead without a refresher changes nothing', () async {
    final engine = fixture.engine(withRefresher: false, refreshAhead: ahead);
    final current = fixture.tokens(inWindow);
    await engine.setTokens(current);

    expect(await engine.validToken(), same(current));
    await settle();

    expect(fixture.refresher.callCount, 0);
  });
}
