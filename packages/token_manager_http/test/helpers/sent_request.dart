import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart';

/// A request the fake inner client received, with its body read.
final class SentRequest {
  /// Records [request] with its [body], sent while [unreadBodies] earlier
  /// response bodies were not read yet.
  const SentRequest(this.request, this.body, {required this.unreadBodies});

  /// The request as the inner client got it.
  final BaseRequest request;

  /// The body bytes.
  final Uint8List body;

  /// How many earlier response bodies were unread when this request was sent.
  final int unreadBodies;

  /// The `Authorization` header, if any.
  String? get authorization => request.headers['authorization'];

  /// The body as UTF-8 text.
  String get text => utf8.decode(body);
}
