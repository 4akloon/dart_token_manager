import 'dart:typed_data';

import 'package:http/http.dart';

/// A response that failed authorization, read to the end so its connection
/// is released before the request is sent again.
///
/// `HttpTokenClient` throws it inside `TokenManager.authorize`, which replays
/// the request on it, and turns it back into a response with [toResponse]
/// when no replay follows. It never reaches the caller.
final class RejectedResponse implements Exception {
  const RejectedResponse._(this._response, this._body);

  final StreamedResponse _response;
  final Uint8List _body;

  /// Reads the body of [response] to the end.
  ///
  /// Throws what the body stream fails with, such as a [ClientException].
  static Future<RejectedResponse> read(StreamedResponse response) async {
    final body = await response.stream.toBytes();
    return RejectedResponse._(response, body);
  }

  /// Whether [error] is a [RejectedResponse].
  static bool matches(Object error) => error is RejectedResponse;

  /// A response like the rejected one whose body is served from memory.
  StreamedResponse toResponse() => switch (_response) {
    BaseResponseWithUrl(:final url) => _BufferedResponseWithUrl(
      _response,
      _body,
      url,
    ),
    _ => _BufferedResponse(_response, _body),
  };

  @override
  String toString() => 'RejectedResponse: HTTP ${_response.statusCode}';
}

/// A copy of a rejected [StreamedResponse] whose body comes from memory.
final class _BufferedResponse extends StreamedResponse {
  _BufferedResponse(StreamedResponse rejected, Uint8List body)
    : super(
        ByteStream.fromBytes(body),
        rejected.statusCode,
        contentLength: body.length,
        request: rejected.request,
        headers: rejected.headers,
        isRedirect: rejected.isRedirect,
        persistentConnection: rejected.persistentConnection,
        reasonPhrase: rejected.reasonPhrase,
      );
}

/// A [_BufferedResponse] that keeps the final [url] of the rejected response.
final class _BufferedResponseWithUrl extends _BufferedResponse
    implements BaseResponseWithUrl {
  _BufferedResponseWithUrl(super.rejected, super.body, this.url);

  @override
  final Uri url;
}
