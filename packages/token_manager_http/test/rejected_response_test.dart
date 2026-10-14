import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:token_manager_http/src/rejected_response.dart';

import 'helpers/rejected_responses.dart';

/// A response that reports its final URL, as `IOClient` returns.
final class _ResponseWithUrl extends StreamedResponse
    implements BaseResponseWithUrl {
  _ResponseWithUrl(this.url) : super(Stream.value(const []), 401);

  @override
  final Uri url;
}

void main() {
  test('serves the whole rejected body from memory', () async {
    final rejection = await RejectedResponse.read(
      RejectedResponses.unauthorized(),
    );

    expect(await rejection.toResponse().stream.bytesToString(), 'denied');
  });

  test('keeps the status, headers, reason and request', () async {
    final original = RejectedResponses.unauthorized();

    final copy = (await RejectedResponse.read(original)).toResponse();

    expect(copy.statusCode, 401);
    expect(copy.headers, original.headers);
    expect(copy.reasonPhrase, 'Unauthorized');
    expect(copy.persistentConnection, isFalse);
    expect(copy.request, same(original.request));
    expect(copy.contentLength, 6);
  });

  test('keeps the url of a response that reports one', () async {
    final redirected = Uri.parse('https://api.example.com/v2/me');

    final copy = (await RejectedResponse.read(
      _ResponseWithUrl(redirected),
    )).toResponse();

    expect(
      copy,
      isA<BaseResponseWithUrl>().having(
        (response) => response.url,
        'url',
        redirected,
      ),
    );
  });

  test('every response gets its own body stream', () async {
    final rejection = await RejectedResponse.read(
      RejectedResponses.unauthorized(),
    );

    await rejection.toResponse().stream.drain<void>();

    expect(await rejection.toResponse().stream.bytesToString(), 'denied');
  });

  test('a body that fails to arrive fails the read', () {
    final broken = RejectedResponses.unauthorized(
      body: Stream.error(ClientException('connection reset')),
    );

    expect(RejectedResponse.read(broken), throwsA(isA<ClientException>()));
  });

  test('matches only a rejected response', () async {
    final rejection = await RejectedResponse.read(
      RejectedResponses.unauthorized(),
    );

    expect(RejectedResponse.matches(rejection), isTrue);
    expect(RejectedResponse.matches(const FormatException()), isFalse);
  });
}
