import 'package:gql_link/gql_link.dart';
import 'package:test/test.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

import 'helpers/link_fixture.dart';

void main() {
  test('a 403 with UNAUTHENTICATED is replayed once and succeeds', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.forbidden(), LinkFixture.ok],
    );

    final events = await fixture.send(fixture.query());

    expect(events, [LinkFixture.ok]);
    expect(fixture.terminal.authorizationOf(1), 'Bearer fresh-1');
    expect(fixture.refresher.calls, 1);
  });

  test(
    'a 403 with UNAUTHENTICATED that fails again is not replayed twice',
    () async {
      final second = LinkFixture.forbidden(code: 'UNAUTHENTICATED');
      final fixture = LinkFixture(outcomes: [LinkFixture.forbidden(), second]);

      final events = await fixture.send(fixture.query());

      expect(events, [second]);
      expect(fixture.terminal.requests, hasLength(2));
      expect(fixture.refresher.calls, 1);
    },
  );

  test('a plain 403 with FORBIDDEN is not replayed', () async {
    final forbidden = LinkFixture.forbidden(code: 'FORBIDDEN');
    final fixture = LinkFixture(outcomes: [forbidden]);

    final events = await fixture.send(fixture.query());

    expect(events, [forbidden]);
    expect(fixture.terminal.requests, hasLength(1));
    expect(fixture.refresher.calls, 0);
  });

  test('a 403 without a parsed response is not replayed', () async {
    const forbidden = ServerException(statusCode: 403);
    final fixture = LinkFixture(outcomes: [forbidden]);

    final events = await fixture.send(fixture.query());

    expect(events, [forbidden]);
    expect(fixture.refresher.calls, 0);
  });

  test('a 403 with UNAUTHENTICATED is replayed whatever statusCodes holds', () {
    const matcher = AuthFailureMatcher(statusCodes: {419});

    expect(matcher.isAuthError(LinkFixture.forbidden()), isTrue);
    expect(matcher.isAuthError(LinkFixture.unauthorized), isFalse);
  });
}
