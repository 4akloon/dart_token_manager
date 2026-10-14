import 'dart:async';

import 'package:http/http.dart';
import 'package:token_manager/token_manager.dart';

import 'client_defaults.dart';
import 'rejected_response.dart';
import 'request_copies.dart';

/// An `http` [Client] that sends requests with the tokens of a
/// [TokenManager] and replays a request once after the server rejects them.
///
/// The client never refreshes by itself: it asks the manager for valid
/// tokens before every request and reports the tokens a server rejected
/// through [TokenManager.authorize], so concurrent requests share one
/// refresh. Every authorized request is sent as a copy, so the caller's
/// request never gets the token header.
///
/// Only a [Request] or an [AbortableRequest] is replayed, because its body is
/// in memory; the rejected body is read first so its connection is released.
/// A [StreamedRequest], a [MultipartRequest] and any other request are sent
/// once, and their rejection is returned as is.
///
/// [close] closes the inner client but not the manager: dispose the manager
/// yourself when the session ends.
///
/// ```dart
/// final client = HttpTokenClient<TokenSet>(manager: manager, inner: Client());
/// final response = await client.get(Uri.parse('https://api.example.com/me'));
/// ```
///
/// {@category getting-started}
final class HttpTokenClient<T> extends BaseClient {
  /// Creates a client that sends through [inner] with the tokens of
  /// [manager].
  ///
  /// [headers] turns tokens into request headers; without it a `TokenSet` is
  /// sent as `Authorization: Bearer <accessToken>`, and any other token type
  /// throws an [ArgumentError]. [isAuthFailure] recognises a rejection, by
  /// default status 401. A request for which [shouldAuthorize] returns
  /// `false`, such as a login, is sent unchanged without tokens.
  HttpTokenClient({
    required TokenManager<T> manager,
    required Client inner,
    Map<String, String> Function(T tokens)? headers,
    bool Function(BaseResponse response)? isAuthFailure,
    bool Function(BaseRequest request)? shouldAuthorize,
  }) : _manager = manager,
       _inner = inner,
       _headers = headers ?? ClientDefaults.bearer,
       _isAuthFailure = isAuthFailure ?? ClientDefaults.isUnauthorized,
       _shouldAuthorize = shouldAuthorize ?? ClientDefaults.authorizesAll {
    ClientDefaults.requireHeaders<T>(headers);
  }

  /// The message of the [ClientException] a request after [close] fails
  /// with.
  static const String _closedMessage = 'HttpTokenClient is closed.';

  static const RequestCopies _copies = RequestCopies();

  final TokenManager<T> _manager;
  final Client _inner;
  final Map<String, String> Function(T tokens) _headers;
  final bool Function(BaseResponse response) _isAuthFailure;
  final bool Function(BaseRequest request) _shouldAuthorize;

  bool _isClosed = false;

  /// Sends [request] with valid tokens, replaying a rejected [Request] once.
  ///
  /// Throws `NotAuthenticated`, `InvalidGrant` or `Transient` when the
  /// manager has no tokens to send, and a [ClientException] after [close].
  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    if (_isClosed) {
      throw ClientException(_closedMessage, request.url);
    }
    if (!_shouldAuthorize(request)) {
      return _inner.send(request);
    }
    return switch (_copies.asReplayable(request)) {
      final Request replayable => _sendReplayable(replayable),
      null => _sendOnce(request),
    };
  }

  /// Closes the inner client once; the [TokenManager] stays open, because
  /// this client does not own it.
  @override
  void close() {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _inner.close();
  }

  /// Sends [request] through [TokenManager.authorize], which replays it once
  /// after a rejection; a rejection that is not replayed is returned.
  Future<StreamedResponse> _sendReplayable(Request request) async {
    try {
      return await _manager.authorize<StreamedResponse>(
        (tokens) => _attempt(request, tokens),
        isAuthFailure: RejectedResponse.matches,
      );
    } on RejectedResponse catch (rejection) {
      return rejection.toResponse();
    }
  }

  /// Sends a copy of [request] with [tokens]; a rejected response is read to
  /// the end and thrown as a [RejectedResponse].
  Future<StreamedResponse> _attempt(Request request, T tokens) async {
    final response = await _inner.send(
      _copies.copyOf(request, _headers(tokens)),
    );
    if (!_isAuthFailure(response)) {
      return response;
    }
    throw await RejectedResponse.read(response);
  }

  /// Sends [request] a single time; a rejection is returned as is and its
  /// tokens are reported, so the next request gets new ones.
  Future<StreamedResponse> _sendOnce(BaseRequest request) async {
    final tokens = await _manager.validToken();
    final response = await _inner.send(
      _copies.streamOf(request, _headers(tokens)),
    );
    if (_isAuthFailure(response)) {
      unawaited(_reportRejected(tokens));
    }
    return response;
  }

  /// Asks the manager to renew [rejected] and ignores the outcome, because
  /// the caller already has the rejected response.
  Future<void> _reportRejected(T rejected) async {
    try {
      await _manager.validToken(rejected: rejected);
    } on Exception {
      // The caller already has the rejected response; a terminal failure
      // still ends the session inside the manager.
    }
  }
}
