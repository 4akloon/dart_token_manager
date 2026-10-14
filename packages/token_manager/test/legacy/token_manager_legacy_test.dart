// These tests exercise the deprecated API on purpose.
// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

final class _MemoryStorage implements TokenStorage<String> {
  String? stored;
  final List<String?> writes = [];

  @override
  String? getTokens() => stored;

  @override
  Future<void> setTokens(String? tokens) async {
    stored = tokens;
    writes.add(tokens);
  }
}

final class _Delegate extends TokenManagerRefreshDelegate<String> {
  _Delegate();

  Completer<String>? pending;

  /// The refresh in flight; fails the test when none was started.
  Completer<String> get awaited =>
      pending ?? (throw StateError('no refresh was started'));

  Object? failWith;
  int calls = 0;

  @override
  Future<String> refresh(String tokens) {
    calls++;
    final error = failWith;
    if (error != null) {
      return Future<String>.error(error);
    }
    return (pending = Completer<String>()).future;
  }
}

void main() {
  late _MemoryStorage storage;
  late _Delegate delegate;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  TokenManager<String> manager({bool withDelegate = true}) {
    return TokenManager<String>(
      storage: storage,
      refreshDelegate: withDelegate ? delegate : null,
    );
  }

  setUp(() {
    storage = _MemoryStorage();
    delegate = _Delegate();
  });

  test('tokens is null until initialize loads the stored tokens', () async {
    storage.stored = 'saved';
    final legacy = manager();
    expect(legacy.tokens, isNull);

    await legacy.initialize();

    expect(legacy.tokens, 'saved');
  });

  test('tokensStream starts with null and then follows the tokens', () async {
    final legacy = manager();
    final seen = expectLater(legacy.tokensStream, emitsInOrder([null, 'a']));

    await legacy.setTokens('a');

    await seen;
  });

  test('tokensStream emits each tokens value once across a refresh', () async {
    final legacy = manager();
    await legacy.setTokens('old');
    final seen = <String?>[];
    legacy.tokensStream.listen(seen.add);

    final refreshing = legacy.executeRefresh();
    await settle();
    delegate.awaited.complete('new');
    await refreshing;
    await settle();

    expect(seen, ['old', 'new']);
  });

  test('tokensStream emits no duplicate after a transient failure', () async {
    delegate.failWith = Exception('offline');
    final legacy = manager();
    await legacy.setTokens('old');
    final seen = <String?>[];
    legacy.tokensStream.listen(seen.add);

    await legacy.executeRefresh();
    await settle();

    expect(seen, ['old']);
  });

  test('tokensStream emits null once on logout', () async {
    final legacy = manager();
    await legacy.setTokens('old');
    final seen = <String?>[];
    legacy.tokensStream.listen(seen.add);

    await legacy.logout();
    await settle();

    expect(seen, ['old', null]);
  });

  test('setTokens persists, and null clears the storage', () async {
    final legacy = manager();
    await legacy.initialize();

    await legacy.setTokens('a');
    await legacy.setTokens(null);

    expect(storage.writes, ['a', null]);
    expect(legacy.tokens, isNull);
  });

  test('executeRefresh replaces the tokens with the delegate result', () async {
    final legacy = manager();
    await legacy.setTokens('old');

    final refreshing = legacy.executeRefresh();
    await settle();
    delegate.awaited.complete('new');
    await refreshing;

    expect(legacy.tokens, 'new');
    expect(storage.stored, 'new');
  });

  test('RevokedTokensException from the delegate logs out', () async {
    delegate.failWith = const RevokedTokensException();
    final legacy = manager();
    await legacy.setTokens('old');

    await legacy.executeRefresh();

    expect(legacy.tokens, isNull);
    expect(storage.stored, isNull);
  });

  test('another exception from the delegate keeps the tokens', () async {
    delegate.failWith = Exception('offline');
    final legacy = manager();
    await legacy.setTokens('old');

    await legacy.executeRefresh();

    expect(legacy.tokens, 'old');
    expect(storage.stored, 'old');
  });

  test('without a delegate executeRefresh does nothing', () async {
    final legacy = manager(withDelegate: false);
    await legacy.setTokens('old');

    await legacy.executeRefresh();

    expect(delegate.calls, 0);
    expect(legacy.tokens, 'old');
  });

  test(
    'waitForFresh is null when idle and completes after the refresh',
    () async {
      final legacy = manager();
      await legacy.setTokens('old');
      expect(legacy.waitForFresh, isNull);

      final refreshing = legacy.executeRefresh();
      await settle();
      final waiting = legacy.waitForFresh;
      expect(waiting, isNotNull);
      delegate.awaited.complete('new');
      await refreshing;
      await waiting;

      expect(legacy.waitForFresh, isNull);
    },
  );

  test('an expired token is refreshed on demand through validToken', () async {
    final legacy = TokenManager<String>(
      storage: storage,
      refreshDelegate: delegate,
      infoDelegate: _AlreadyExpired(),
    );
    await legacy.setTokens('stale');

    final valid = legacy.validToken();
    await settle();
    delegate.awaited.complete('fresh');

    expect(await valid, 'fresh');
  });
}

final class _AlreadyExpired implements TokenInfoDelegate<String> {
  @override
  DateTime? expiresAt(String tokens) => DateTime.utc(2000);
}
