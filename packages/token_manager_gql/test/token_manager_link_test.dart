import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

import 'helpers/link_fixture.dart';

void main() {
  test('attaches the header built from valid tokens', () async {
    final fixture = LinkFixture(outcomes: [LinkFixture.ok]);

    final events = await fixture.send(fixture.query());

    expect(events, [LinkFixture.ok]);
    expect(fixture.terminal.authorizationOf(0), 'Bearer old');
  });

  test('keeps the headers the request already carries', () async {
    final fixture = LinkFixture(outcomes: [LinkFixture.ok]);
    const traced = HttpLinkHeaders(headers: {'X-Trace': '1'});

    await fixture.send(
      fixture.query(context: const Context().withEntry(traced)),
    );

    final headers = fixture.terminal.requests.single.context
        .entry<HttpLinkHeaders>()
        ?.headers;
    expect(headers, {'X-Trace': '1', 'Authorization': 'Bearer old'});
  });

  test('the token header replaces the same header on the request', () async {
    final fixture = LinkFixture(outcomes: [LinkFixture.ok]);
    const stale = HttpLinkHeaders(headers: {'Authorization': 'Bearer stale'});

    await fixture.send(
      fixture.query(context: const Context().withEntry(stale)),
    );

    expect(fixture.terminal.authorizationOf(0), 'Bearer old');
  });

  test('replays once with refreshed tokens after a 401 error event', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.unauthorized, LinkFixture.ok],
    );

    final events = await fixture.send(fixture.query());

    expect(events, [LinkFixture.ok]);
    expect(fixture.terminal.authorizationOf(1), 'Bearer fresh-1');
    expect(fixture.refresher.calls, 1);
  });

  test(
    'a persistent 401 is replayed exactly once and then delivered',
    () async {
      final fixture = LinkFixture(
        outcomes: [LinkFixture.unauthorized, LinkFixture.unauthorized],
      );

      final events = await fixture.send(fixture.query());

      expect(events, [LinkFixture.unauthorized]);
      expect(fixture.terminal.requests, hasLength(2));
    },
  );

  test(
    'an error the matcher does not accept is delivered unreplayed',
    () async {
      const failure = ServerException(statusCode: 500);
      final fixture = LinkFixture(outcomes: [failure]);

      final events = await fixture.send(fixture.query());

      expect(events, [failure]);
      expect(fixture.refresher.calls, 0);
    },
  );

  test('a terminal refresh failure during the replay is delivered', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.unauthorized, LinkFixture.ok],
      refreshFailure: const InvalidGrant(),
    );

    final events = await fixture.send(fixture.query());

    expect(events, [isA<InvalidGrant>()]);
    expect(fixture.terminal.requests, hasLength(1));
  });

  test('every attempt is built from the original request', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.unauthorized, LinkFixture.ok],
    );
    const traced = HttpLinkHeaders(headers: {'X-Trace': '1'});
    final original = fixture.query(context: const Context().withEntry(traced));

    await fixture.send(original);

    final expected = original.withContextEntry(
      const HttpLinkHeaders(
        headers: {'X-Trace': '1', 'Authorization': 'Bearer fresh-1'},
      ),
    );
    expect(fixture.terminal.requests[1], expected);
  });

  test('concurrent rejected requests share one refresh', () async {
    final fixture = LinkFixture(
      outcomes: [
        LinkFixture.unauthorized,
        LinkFixture.unauthorized,
        LinkFixture.ok,
        LinkFixture.ok,
      ],
    );

    final results = await Future.wait([
      fixture.send(fixture.query()),
      fixture.send(fixture.query()),
    ]);

    expect(results, [
      [LinkFixture.ok],
      [LinkFixture.ok],
    ]);
    expect(fixture.refresher.calls, 1);
    // Two first attempts plus one replay per rejected request.
    expect(fixture.terminal.requests, hasLength(4));
  });

  test(
    'a request marked with SkipAuthorization is sent without tokens',
    () async {
      final fixture = LinkFixture(
        outcomes: [LinkFixture.ok],
        isSignedIn: false,
      );
      final anonymous = fixture.query(
        context: const Context().withEntry(const SkipAuthorization()),
      );

      final events = await fixture.send(anonymous);

      expect(events, [LinkFixture.ok]);
      expect(fixture.terminal.requests.single, anonymous);
    },
  );

  test('a request without a session fails with NotAuthenticated', () async {
    final fixture = LinkFixture(outcomes: [LinkFixture.ok], isSignedIn: false);

    final events = await fixture.send(fixture.query());

    expect(events, [isA<NotAuthenticated>()]);
    expect(fixture.terminal.requests, isEmpty);
  });

  test('throws a StateError when it terminates the chain', () {
    final fixture = LinkFixture();
    final link = TokenManagerLink<TokenSet>(
      manager: fixture.manager,
      headers: (tokens) => const {},
    );

    expect(() => link.request(fixture.query()), throwsStateError);
  });
}
