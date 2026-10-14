# Testing

`HttpTokenClient` wraps any `Client`, so tests pass a `MockClient` from
`package:http/testing.dart` as `inner` and an `InMemoryTokenStore` to the
manager. Nothing touches the network.

```dart
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

final class _FixedRefresher implements TokenRefresher<TokenSet> {
  int calls = 0;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    calls++;
    return const TokenSet(accessToken: 'fresh');
  }
}

void main() {
  test('a stale token is refreshed once and the request replayed', () async {
    final refresher = _FixedRefresher();
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(const TokenSet(accessToken: 'stale')),
      refresher: refresher,
    );
    final server = MockClient((request) async =>
        request.headers['authorization'] == 'Bearer fresh'
            ? Response('ok', 200)
            : Response('expired', 401));
    final client = HttpTokenClient<TokenSet>(manager: manager, inner: server);

    final response = await client.get(Uri.parse('https://api.example.com/me'));

    expect(response.statusCode, 200);
    expect(refresher.calls, 1);
  });
}
```

Tips:

- **Read the header in lower case.** `request.headers` of `package:http` is
  case-insensitive, so `headers['authorization']` finds `Authorization`.
- **Test the refresh failures.** Make the refresher throw `InvalidGrant` to
  test the sign-out path, and `Transient` to test that the session stays.
- **Pump the event queue after an unreplayed rejection.** A rejected
  `StreamedRequest` reports its tokens without waiting; call
  `await pumpEventQueue()` before you check `manager.states` or the
  refresher.
- **Close what you create.** `client.close()` closes the `MockClient`;
  `manager.dispose()` closes the manager.
