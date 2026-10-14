import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One request the adapter saw.
final class RecordedRequest {
  /// Creates a record.
  const RecordedRequest({
    required this.uri,
    required this.authorization,
    required this.body,
  });

  /// The full address.
  final Uri uri;

  /// The `Authorization` header, or `null` when there was none.
  final String? authorization;

  /// The request body as text; empty when there was none.
  final String body;
}

/// An adapter that answers 200 to one `Authorization` value and 401 to all
/// others, and records every request. No network is used.
final class FakeHttpAdapter implements HttpClientAdapter {
  /// Creates an adapter that accepts only [accepted].
  FakeHttpAdapter({required this.accepted, this.successBody = '{"ok":true}'});

  /// The only `Authorization` value that gets a 200.
  final String accepted;

  /// The body of a 200 answer.
  String successBody;

  /// Every request in arrival order.
  final List<RecordedRequest> requests = [];

  /// When set, an answer waits until it completes.
  Completer<void>? gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final chunks = await requestStream?.toList() ?? const <Uint8List>[];
    final authorization = options.headers['Authorization'];
    requests.add(
      RecordedRequest(
        uri: options.uri,
        authorization: authorization is String ? authorization : null,
        body: utf8.decode(chunks.expand((chunk) => chunk).toList()),
      ),
    );
    await gate?.future;
    final ok = authorization == accepted;
    return ResponseBody.fromString(
      ok ? successBody : '',
      ok ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
