import 'package:test/test.dart';
import 'package:token_manager/src/engine/authorized_call.dart';
import 'package:token_manager/src/refresh_failure.dart';
import 'package:token_manager/src/token_set.dart';

import '../helpers/engine_fixture.dart';

final class _Unauthorized implements Exception {
  const _Unauthorized();
}

final class _Cancelled implements Exception {
  const _Cancelled();
}

void main() {
  late EngineFixture fixture;

  setUp(() => fixture = EngineFixture());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  bool isUnauthorized(Object error) => error is _Unauthorized;

  test('sends once with the current tokens', () async {
    final tokens = fixture.tokens(const Duration(hours: 1));
    final engine = fixture.engine();
    await engine.setTokens(tokens);
    final sent = <TokenSet>[];

    final result = await AuthorizedCall(engine).run<String>(
      (used) async {
        sent.add(used);
        return 'ok';
      },
      isAuthFailure: isUnauthorized,
    );

    expect(result, 'ok');
    expect(sent.single, same(tokens));
  });

  test('replays once with refreshed tokens after an auth failure', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(hours: 1));
    await engine.setTokens(old);
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    final sent = <TokenSet>[];

    final result = AuthorizedCall(engine).run<String>(
      (used) async {
        sent.add(used);
        if (identical(used, old)) {
          throw const _Unauthorized();
        }
        return 'ok';
      },
      isAuthFailure: isUnauthorized,
    );
    await settle();
    fixture.refresher.complete(fresh);

    expect(await result, 'ok');
    expect(sent, [same(old), same(fresh)]);
  });

  test('a second auth failure propagates after exactly one replay', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(hours: 1)));
    var sends = 0;

    final result = expectLater(
      AuthorizedCall(engine).run<String>(
        (used) async {
          sends++;
          throw const _Unauthorized();
        },
        isAuthFailure: isUnauthorized,
      ),
      throwsA(isA<_Unauthorized>()),
    );
    await settle();
    fixture.refresher.complete(fixture.tokens(const Duration(hours: 1)));
    await result;

    expect(sends, 2);
    expect(fixture.refresher.callCount, 1);
  });

  test('a failure that is not an auth failure never refreshes', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(hours: 1)));

    await expectLater(
      AuthorizedCall(engine).run<String>(
        (used) async => throw StateError('boom'),
        isAuthFailure: isUnauthorized,
      ),
      throwsStateError,
    );

    expect(fixture.refresher.callCount, 0);
  });

  test('concurrent auth failures cause one refresh', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(hours: 1));
    await engine.setTokens(old);
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');

    Future<String> call() => AuthorizedCall(engine).run<String>(
      (used) async {
        if (identical(used, old)) {
          throw const _Unauthorized();
        }
        return 'ok';
      },
      isAuthFailure: isUnauthorized,
    );

    final first = call();
    final second = call();
    await settle();
    fixture.refresher.complete(fresh);

    expect(await first, 'ok');
    expect(await second, 'ok');
    expect(fixture.refresher.callCount, 1);
  });

  test('tokens replaced during the call are used for the replay without a '
      'refresh', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(hours: 1));
    await engine.setTokens(old);
    final fresh = fixture.tokens(const Duration(hours: 1), access: 'b');
    final sent = <TokenSet>[];

    final result = await AuthorizedCall(engine).run<String>(
      (used) async {
        sent.add(used);
        if (identical(used, old)) {
          await engine.setTokens(fresh);
          throw const _Unauthorized();
        }
        return 'ok';
      },
      isAuthFailure: isUnauthorized,
    );

    expect(result, 'ok');
    expect(sent, [same(old), same(fresh)]);
    expect(fixture.refresher.callCount, 0);
  });

  test('without a refresher the original auth failure is rethrown', () async {
    final engine = fixture.engine(withRefresher: false);
    await engine.setTokens(fixture.tokens(const Duration(hours: 1)));
    var sends = 0;

    await expectLater(
      AuthorizedCall(engine).run<String>(
        (used) async {
          sends++;
          throw const _Unauthorized();
        },
        isAuthFailure: isUnauthorized,
      ),
      throwsA(isA<_Unauthorized>()),
    );

    expect(sends, 1);
  });

  test('InvalidGrant from the refresh propagates to the caller', () async {
    final engine = fixture.engine();
    await engine.setTokens(fixture.tokens(const Duration(hours: 1)));

    final result = expectLater(
      AuthorizedCall(engine).run<String>(
        (used) async => throw const _Unauthorized(),
        isAuthFailure: isUnauthorized,
      ),
      throwsA(isA<InvalidGrant>()),
    );
    await settle();
    fixture.refresher.fail(const InvalidGrant());
    await result;
  });

  test('an exception that send throws on the replay fails the call', () async {
    final engine = fixture.engine();
    final old = fixture.tokens(const Duration(hours: 1));
    await engine.setTokens(old);
    var sends = 0;

    final result = AuthorizedCall(engine).run<String>(
      (used) {
        sends++;
        if (identical(used, old)) {
          return Future<String>.error(const _Unauthorized());
        }
        throw const _Cancelled();
      },
      isAuthFailure: isUnauthorized,
    );
    await settle();
    fixture.refresher.complete(
      fixture.tokens(const Duration(hours: 1), access: 'b'),
    );

    await expectLater(result, throwsA(isA<_Cancelled>()));
    expect(sends, 2);
  });
}
