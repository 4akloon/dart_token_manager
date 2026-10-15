import 'package:test/test.dart';
import 'package:token_manager/src/engine/refresh_policy.dart';
import 'package:token_manager/src/token_info.dart';

import '../helpers/fake_clock.dart';

final class _FixedInfo implements TokenInfo<List<int>> {
  const _FixedInfo(this.expiry);

  final DateTime? expiry;

  @override
  DateTime? expiresAt(List<int> tokens) => expiry;
}

void main() {
  final start = DateTime.utc(2026, 1, 1);
  const skew = Duration(seconds: 30);

  RefreshPolicy<List<int>> policy({
    DateTime? expiry,
    FakeClock? clock,
    Duration? refreshAhead,
  }) {
    return RefreshPolicy<List<int>>(
      skew: skew,
      refreshAhead: refreshAhead,
      clock: clock ?? FakeClock(start),
      info: expiry == null ? null : _FixedInfo(expiry),
    );
  }

  test('the rejected token itself needs a refresh', () {
    final tokens = [1];

    expect(policy().needsRefresh(tokens, tokens), isTrue);
  });

  test('an equal but different rejected token does not need a refresh', () {
    expect(policy().needsRefresh([1], [1]), isFalse);
  });

  test('without info and a rejected token nothing needs a refresh', () {
    expect(policy().needsRefresh([1], null), isFalse);
  });

  test('tokens that never expire do not need a refresh', () {
    final noExpiry = RefreshPolicy<List<int>>(
      skew: skew,
      clock: FakeClock(start),
      info: const _FixedInfo(null),
    );

    expect(noExpiry.needsRefresh([1], null), isFalse);
  });

  test('tokens expiring inside the skew need a refresh', () {
    final soon = start.add(const Duration(seconds: 10));

    expect(policy(expiry: soon).needsRefresh([1], null), isTrue);
  });

  test('tokens expiring exactly at the skew boundary need a refresh', () {
    final boundary = start.add(skew);

    expect(policy(expiry: boundary).needsRefresh([1], null), isTrue);
  });

  test('tokens expiring after the skew do not need a refresh', () {
    final later = start.add(skew + const Duration(seconds: 1));

    expect(policy(expiry: later).needsRefresh([1], null), isFalse);
  });

  test('the clock is read at every call', () {
    final clock = FakeClock(start);
    final subject = policy(
      expiry: start.add(const Duration(minutes: 5)),
      clock: clock,
    );
    final tokens = [1];

    expect(subject.needsRefresh(tokens, null), isFalse);
    clock.advance(const Duration(minutes: 5));
    expect(subject.needsRefresh(tokens, null), isTrue);
  });

  group('isExpiring', () {
    test('is true when less than the window is left', () {
      final subject = policy(expiry: start.add(const Duration(minutes: 2)));

      expect(subject.isExpiring([1], const Duration(minutes: 3)), isTrue);
    });

    test('is false when more than the window is left', () {
      final subject = policy(expiry: start.add(const Duration(minutes: 2)));

      expect(subject.isExpiring([1], const Duration(minutes: 1)), isFalse);
    });

    test('is true exactly at the window boundary', () {
      final subject = policy(expiry: start.add(const Duration(minutes: 2)));

      expect(subject.isExpiring([1], const Duration(minutes: 2)), isTrue);
    });

    test('is false for tokens that never expire', () {
      expect(policy().isExpiring([1], const Duration(days: 365)), isFalse);
    });
  });

  group('needsAheadRefresh', () {
    const ahead = Duration(minutes: 5);

    test('is false without a refreshAhead window', () {
      final subject = policy(expiry: start.add(const Duration(minutes: 1)));

      expect(subject.needsAheadRefresh([1]), isFalse);
    });

    test('is true inside the window', () {
      final subject = policy(
        expiry: start.add(const Duration(minutes: 3)),
        refreshAhead: ahead,
      );

      expect(subject.needsAheadRefresh([1]), isTrue);
    });

    test('is true exactly at the window boundary', () {
      final subject = policy(expiry: start.add(ahead), refreshAhead: ahead);

      expect(subject.needsAheadRefresh([1]), isTrue);
    });

    test('is false outside the window', () {
      final subject = policy(
        expiry: start.add(const Duration(minutes: 6)),
        refreshAhead: ahead,
      );

      expect(subject.needsAheadRefresh([1]), isFalse);
    });

    test('is false for tokens that never expire', () {
      expect(policy(refreshAhead: ahead).needsAheadRefresh([1]), isFalse);
    });
  });

  group('window', () {
    test('is the skew without a refreshAhead window', () {
      expect(policy().window, skew);
    });

    test('is refreshAhead when set', () {
      expect(
        policy(refreshAhead: const Duration(minutes: 5)).window,
        const Duration(minutes: 5),
      );
    });
  });

  group('refreshAhead validation', () {
    test('equal to the skew is rejected', () {
      expect(
        () => policy(refreshAhead: skew),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'refreshAhead',
          ),
        ),
      );
    });

    test('shorter than the skew is rejected', () {
      expect(
        () => policy(refreshAhead: const Duration(seconds: 10)),
        throwsArgumentError,
      );
    });

    test('longer than the skew is accepted', () {
      expect(
        () => policy(refreshAhead: const Duration(seconds: 31)),
        returnsNormally,
      );
    });
  });
}
