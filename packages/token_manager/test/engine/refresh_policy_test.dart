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

  RefreshPolicy<List<int>> policy({DateTime? expiry, FakeClock? clock}) {
    return RefreshPolicy<List<int>>(
      skew: skew,
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
}
