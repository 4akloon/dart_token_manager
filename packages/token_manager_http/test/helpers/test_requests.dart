import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';

import 'client_fixture.dart';
import 'fake_answer.dart';
import 'sent_request.dart';

/// Shared answers and requests for the client tests.
final class TestRequests {
  const TestRequests._();

  /// An answer callback that always says 200.
  static FakeAnswer alwaysOk(SentRequest request) => FakeAnswer.ok;

  /// A POST [StreamedRequest] to [ClientFixture.url] whose body is [body].
  static StreamedRequest streamed(String body) {
    final request = StreamedRequest('POST', ClientFixture.url);
    request.sink.add(utf8.encode(body));
    unawaited(request.sink.close());
    return request;
  }
}
