import 'dart:async';

import 'package:http/http.dart';

/// Builds the requests `HttpTokenClient` sends in place of the caller's, so
/// the caller's request never gets the token header.
final class RequestCopies {
  /// Creates the helper.
  const RequestCopies();

  /// Returns [request] as a [Request] when it can be copied and sent again,
  /// or `null` when its body can be sent only once.
  ///
  /// A subclass of [Request] other than [AbortableRequest] may build its body
  /// in `finalize`, so it is sent once like a streamed request.
  Request? asReplayable(BaseRequest request) => switch (request) {
    final AbortableRequest abortable => abortable,
    final Request plain when plain.runtimeType == Request => plain,
    _ => null,
  };

  /// Returns a copy of [original] with [headers] added.
  ///
  /// [original] stays unchanged and unsent, so it can be copied again for a
  /// replay. An abort trigger is kept.
  Request copyOf(Request original, Map<String, String> headers) {
    final copy = switch (original) {
      final AbortableRequest abortable => AbortableRequest(
        original.method,
        original.url,
        abortTrigger: abortable.abortTrigger,
      ),
      _ => Request(original.method, original.url),
    };
    _copyEncoding(original, copy);
    copy
      ..headers.addAll(original.headers)
      ..headers.addAll(headers)
      ..bodyBytes = original.bodyBytes
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
    return copy;
  }

  /// Returns a request that streams the body of [original] with [headers]
  /// added.
  ///
  /// [original] is finalized, as sending it would, but the token header is
  /// never added to it. An abort trigger is kept.
  StreamedRequest streamOf(BaseRequest original, Map<String, String> headers) {
    // Finalize first: a MultipartRequest sets its content type there.
    final body = original.finalize();
    final copy = switch (original) {
      Abortable(:final abortTrigger) => AbortableStreamedRequest(
        original.method,
        original.url,
        abortTrigger: abortTrigger,
      ),
      _ => StreamedRequest(original.method, original.url),
    };
    copy
      ..headers.addAll(original.headers)
      ..headers.addAll(headers)
      ..contentLength = original.contentLength
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
    unawaited(copy.sink.addStream(body).whenComplete(copy.sink.close));
    return copy;
  }

  /// Gives [copy] the encoding of [original] while [copy] has no content type
  /// yet, so the charset of a copied content type is never rewritten.
  void _copyEncoding(Request original, Request copy) {
    try {
      copy.encoding = original.encoding;
    } on FormatException {
      // The content type names a charset Dart does not know; the copied
      // header carries it and the default encoding is never read.
    }
  }
}
