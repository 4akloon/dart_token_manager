import 'dart:convert';

import 'package:http/http.dart';

/// Rejected responses for the response tests.
final class RejectedResponses {
  const RejectedResponses._();

  /// A 401 response whose body is `denied` unless [body] is given.
  static StreamedResponse unauthorized({Stream<List<int>>? body}) =>
      StreamedResponse(
        body ?? Stream.value(utf8.encode('denied')),
        401,
        request: Request('GET', Uri.parse('https://api.example.com/me')),
        headers: const {'www-authenticate': 'Bearer error="invalid_token"'},
        reasonPhrase: 'Unauthorized',
        persistentConnection: false,
      );
}
