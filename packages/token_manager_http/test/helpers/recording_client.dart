import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';

import 'fake_answer.dart';
import 'sent_request.dart';

/// An inner client that answers from a callback, records every request and
/// counts [close] calls; it never opens a socket.
final class RecordingClient extends BaseClient {
  /// Answers with [answer]; by default 401 to the token `old` and 200 to any
  /// other.
  RecordingClient({FutureOr<FakeAnswer> Function(SentRequest request)? answer})
    : _answer = answer ?? _byToken;

  final FutureOr<FakeAnswer> Function(SentRequest request) _answer;
  int _unreadBodies = 0;
  int _closeCalls = 0;

  /// The requests received, in order.
  final List<SentRequest> requests = [];

  /// How many times [close] was called.
  int get closeCalls => _closeCalls;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final sent = SentRequest(request, body, unreadBodies: _unreadBodies);
    requests.add(sent);
    final answer = await _answer(sent);
    return StreamedResponse(_bodyOf(answer), answer.status, request: request);
  }

  @override
  void close() {
    _closeCalls++;
  }

  /// A single-subscription body that counts as unread until it is done.
  Stream<List<int>> _bodyOf(FakeAnswer answer) {
    _unreadBodies++;
    return Stream<List<int>>.multi((listener) {
      listener.add(utf8.encode(answer.body));
      final failure = answer.failure;
      if (failure != null) {
        listener.addError(failure);
      }
      unawaited(listener.close().whenComplete(() => _unreadBodies--));
    });
  }

  static FakeAnswer _byToken(SentRequest request) =>
      request.authorization == 'Bearer old'
      ? FakeAnswer.unauthorized
      : FakeAnswer.ok;
}
