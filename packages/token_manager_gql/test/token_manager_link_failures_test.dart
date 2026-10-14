import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

import 'helpers/link_fixture.dart';

void main() {
  test('NotAuthenticated arrives as a LinkException', () async {
    final fixture = LinkFixture(outcomes: [LinkFixture.ok], isSignedIn: false);

    final events = await fixture.send(fixture.query());

    final error = events.single as LinkException;
    expect(error.originalException, isA<NotAuthenticated>());
    expect(error.originalStackTrace, isNotNull);
  });

  test('InvalidGrant arrives as a LinkException', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.unauthorized],
      refreshFailure: const InvalidGrant(),
    );

    final events = await fixture.send(fixture.query());

    expect(
      (events.single as LinkException).originalException,
      isA<InvalidGrant>(),
    );
  });

  test('Transient arrives as a LinkException', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.unauthorized],
      refreshFailure: Transient(Exception('offline')),
    );

    final events = await fixture.send(fixture.query());

    expect(
      (events.single as LinkException).originalException,
      isA<Transient>(),
    );
  });

  test('a ServerException is delivered as is, not wrapped', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.unauthorized, LinkFixture.unauthorized],
    );

    final events = await fixture.send(fixture.query());

    expect(events.single, same(LinkFixture.unauthorized));
  });

  test('a skip-authorization request is forwarded unchanged', () async {
    final fixture = LinkFixture(
      outcomes: [LinkFixture.forbidden()],
      isSignedIn: false,
    );
    final request = fixture.query(
      context: const Context().withEntry(const SkipAuthorization()),
    );

    final events = await fixture.send(request);

    expect(events.single, isA<ServerException>());
    expect(fixture.refresher.calls, 0);
    expect(fixture.terminal.authorizationOf(0), isNull);
  });
}
