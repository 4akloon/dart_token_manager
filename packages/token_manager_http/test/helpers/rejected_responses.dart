import 'dart:convert';

import 'package:http/http.dart';

/// Rejected responses for the response tests.
final class RejectedResponses {
  const RejectedResponses._();

  /// A 401 response whose body is `denied` unless [body] is given, and which
  /// followed a redirect when [isRedirect].
  static StreamedResponse unauthorized({
    Stream<List<int>>? body,
    bool isRedirect = false,
  }) => StreamedResponse(
    body ?? Stream.value(utf8.encode('denied')),
    401,
    request: Request('GET', Uri.parse('https://api.example.com/me')),
    headers: const {'www-authenticate': 'Bearer error="invalid_token"'},
    reasonPhrase: 'Unauthorized',
    persistentConnection: false,
    isRedirect: isRedirect,
  );
}
