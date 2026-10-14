import 'package:test/test.dart';

import 'helpers/link_fixture.dart';

void main() {
  test('nothing is sent until the stream is listened to', () async {
    final fixture = LinkFixture(outcomes: [LinkFixture.ok]);

    final stream = fixture.link.request(fixture.query());
    await pumpEventQueue();
    expect(fixture.terminal.requests, isEmpty);

    await expectLater(stream, emitsInOrder([LinkFixture.ok, emitsDone]));
  });

  test('pause reaches the terminating link', () async {
    final fixture = LinkFixture();
    final subscription = fixture.link.request(fixture.query()).listen(null);
    await pumpEventQueue();

    subscription.pause();

    expect(fixture.terminal.controllers.single.isPaused, isTrue);
    await subscription.cancel();
  });

  test('resume reaches the terminating link', () async {
    final fixture = LinkFixture();
    final subscription = fixture.link.request(fixture.query()).listen(null);
    await pumpEventQueue();
    subscription.pause();

    subscription.resume();

    expect(fixture.terminal.controllers.single.isPaused, isFalse);
    await subscription.cancel();
  });

  test('cancel reaches the terminating link', () async {
    final fixture = LinkFixture();
    final subscription = fixture.link.request(fixture.query()).listen(null);
    await pumpEventQueue();

    await subscription.cancel();

    expect(fixture.terminal.controllers.single.hasListener, isFalse);
  });

  test('cancelling before the tokens arrive never sends the request', () async {
    final fixture = LinkFixture();
    final subscription = fixture.link.request(fixture.query()).listen(null);

    await subscription.cancel();
    await pumpEventQueue();

    expect(fixture.terminal.requests, isEmpty);
  });

  test('a 401 after the first response is delivered unreplayed', () async {
    final fixture = LinkFixture();
    final events = <Object>[];
    final subscription = fixture.link
        .request(fixture.query())
        .listen(events.add, onError: events.add);
    await pumpEventQueue();

    fixture.terminal.controllers.single
      ..add(LinkFixture.ok)
      ..addError(LinkFixture.unauthorized);
    await pumpEventQueue();

    expect(events, [LinkFixture.ok, LinkFixture.unauthorized]);
    expect(fixture.terminal.requests, hasLength(1));
    await subscription.cancel();
  });
}
