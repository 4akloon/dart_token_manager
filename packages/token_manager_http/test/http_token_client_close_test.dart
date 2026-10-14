import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager/token_manager.dart';

import 'helpers/client_fixture.dart';

void main() {
  test('close closes the inner client', () {
    final fixture = ClientFixture();

    fixture.client.close();

    expect(fixture.inner.closeCalls, 1);
  });

  test('closing twice closes the inner client once', () {
    final fixture = ClientFixture();

    fixture.client
      ..close()
      ..close();

    expect(fixture.inner.closeCalls, 1);
  });

  test('close does not dispose the manager', () async {
    final fixture = ClientFixture();

    fixture.client.close();

    await expectLater(
      fixture.manager.setTokens(const TokenSet(accessToken: 'next')),
      completes,
    );
    expect(await fixture.manager.validToken(), isA<TokenSet>());
  });

  test('a request after close fails without asking for tokens', () async {
    final fixture = ClientFixture(isSignedIn: false);

    fixture.client.close();

    await expectLater(
      fixture.client.get(ClientFixture.url),
      throwsA(isA<ClientException>()),
    );
    expect(fixture.inner.requests, isEmpty);
  });

  test('a request that is not authorized still fails after close', () async {
    final fixture = ClientFixture();
    final client = fixture.clientWith(shouldAuthorize: (_) => false);

    client.close();

    await expectLater(
      client.get(ClientFixture.url),
      throwsA(isA<ClientException>()),
    );
    expect(fixture.inner.requests, isEmpty);
  });
}
