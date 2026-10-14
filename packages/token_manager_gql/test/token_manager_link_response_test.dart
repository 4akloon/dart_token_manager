import 'package:test/test.dart';

import 'helpers/link_fixture.dart';

void main() {
  test('replays an UNAUTHENTICATED response that has no data', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.rejected(), LinkFixture.ok],
    );

    final events = await fixture.send(fixture.query());

    expect(events, [LinkFixture.ok]);
    expect(fixture.terminal.authorizationOf(1), 'Bearer fresh-1');
    expect(fixture.refresher.calls, 1);
  });

  test('delivers an UNAUTHENTICATED response with data unreplayed', () async {
    final partial = LinkFixture.rejected(data: {'createPost': null});
    final fixture = LinkFixture(outcomes: [partial, LinkFixture.ok]);

    final events = await fixture.send(fixture.query());

    expect(events, [partial]);
    expect(fixture.terminal.requests, hasLength(1));
    expect(fixture.refresher.calls, 0);
  });

  test('a persistent UNAUTHENTICATED response is replayed once and then '
      'delivered as a response', () async {
    final first = LinkFixture.rejected();
    final second = LinkFixture.rejected(message: 'still not signed in');
    final fixture = LinkFixture(outcomes: [first, second]);

    final events = await fixture.send(fixture.query());

    expect(events, [second]);
    expect(fixture.terminal.requests, hasLength(2));
  });

  test('without a refresher the UNAUTHENTICATED response is delivered as '
      'is', () async {
    final rejected = LinkFixture.rejected();
    final fixture = LinkFixture(outcomes: [rejected], hasRefresher: false);

    final events = await fixture.send(fixture.query());

    expect(events, [rejected]);
    expect(fixture.terminal.requests, hasLength(1));
  });

  test('a response with another error code is delivered unreplayed', () async {
    final forbidden = LinkFixture.rejected(code: 'FORBIDDEN');
    final fixture = LinkFixture(outcomes: [forbidden]);

    final events = await fixture.send(fixture.query());

    expect(events, [forbidden]);
    expect(fixture.refresher.calls, 0);
  });
}
