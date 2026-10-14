import 'package:token_manager/src/engine/token_engine.dart';
import 'package:token_manager/src/token_set.dart';
import 'package:token_manager/src/token_set_info.dart';

import 'fake_clock.dart';
import 'fake_refresher.dart';
import 'fake_token_store.dart';

/// Wires a [TokenEngine] to fakes and builds token sets relative to its clock.
final class EngineFixture {
  /// Creates a fixture whose clock starts at 2026-01-01 UTC.
  EngineFixture()
    : clock = FakeClock(DateTime.utc(2026)),
      store = FakeTokenStore<TokenSet>(),
      refresher = FakeRefresher<TokenSet>();

  /// The engine's clock.
  final FakeClock clock;

  /// The engine's store.
  final FakeTokenStore<TokenSet> store;

  /// The engine's refresher.
  final FakeRefresher<TokenSet> refresher;

  /// Builds an engine with a 30 second skew.
  TokenEngine<TokenSet> engine({bool withRefresher = true}) {
    return TokenEngine<TokenSet>(
      store: store,
      skew: const Duration(seconds: 30),
      clock: clock,
      refresher: withRefresher ? refresher : null,
      info: const TokenSetInfo(),
    );
  }

  /// Builds tokens that expire [life] after the fixture's current time.
  TokenSet tokens(Duration life, {String access = 'a'}) {
    return TokenSet(
      accessToken: access,
      refreshToken: 'r',
      expiresAt: clock.now().add(life),
    );
  }
}
