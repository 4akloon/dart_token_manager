# Testing

Everything time- and I/O-dependent is a seam you can replace: `Clock`,
`TokenStore` and `TokenRefresher`.

```dart
import 'package:token_manager/token_manager.dart';

final class FixedClock implements Clock {
  FixedClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}

final class CountingRefresher implements TokenRefresher<TokenSet> {
  int calls = 0;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    calls++;
    return TokenSet(accessToken: 'fresh', expiresAt: DateTime.utc(2030));
  }
}

Future<void> expiryRefreshes() async {
  final clock = FixedClock(DateTime.utc(2026));
  final refresher = CountingRefresher();
  final manager = TokenManager<TokenSet>.create(
    store: InMemoryTokenStore<TokenSet>(),
    refresher: refresher,
    info: const TokenSetInfo(),
    clock: clock,
  );
  await manager.setTokens(
    TokenSet(accessToken: 'old', expiresAt: DateTime.utc(2026, 1, 1, 0, 1)),
  );

  await manager.validToken(); // a minute left: no refresh
  clock.current = DateTime.utc(2026, 1, 1, 0, 0, 40); // inside the skew
  await manager.validToken(); // refreshes

  print(refresher.calls); // 1
}
```

`Clock` is a plain class with a `now()` method, so an implementation with a
settable time is enough. Use `InMemoryTokenStore` when the store is not under
test.

## How this package's tests are built

`test/` mirrors `lib/src/`; the shared fakes are in `test/helpers/`:

| Helper | Purpose |
|---|---|
| `FakeClock` | Time moves only through `advance`. |
| `FakeRefresher` | Each call stays pending until the test completes or fails it, so races are deterministic. |
| `FakeTokenStore` | Counts reads, writes and deletes, logs their order, and throws or blocks on demand. |
| `EngineFixture` | Wires an engine to the three fakes with a 30 second skew. |

Concurrency tests start several callers, check that the refresher ran once,
and only then complete the pending call. No test uses the network. Each test
checks one behaviour and is named after it; the size limits are enforced by
`test/quality/size_limits_test.dart`.

## Where to go next

- [Concepts](concepts.md) — the rules these tests pin down.
