import 'dart:async';

import 'package:http/http.dart';
import 'package:token_manager/token_manager.dart';

import 'request_copies.dart';

/// An `http` [Client] that sends requests with the tokens of a
/// [TokenManager].
///
/// The client never refreshes by itself: it asks the manager for valid
/// tokens before every request and reports the tokens a server rejected, so
/// concurrent requests share one refresh. Every request is sent as a copy,
/// so the caller's request never gets the token header.
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
       _headers = headers ?? _bearer,
       _isAuthFailure = isAuthFailure ?? _isUnauthorized,
       _shouldAuthorize = shouldAuthorize ?? _authorizesAll {
    if (headers == null && T != TokenSet) {
      throw ArgumentError.value(
        headers,
        'headers',
        'is required unless the token type is TokenSet',
      );
    }
  }

  /// The status that rejects the tokens unless [isAuthFailure] says
  /// otherwise.
  static const int _unauthorized = 401;

  static const RequestCopies _copies = RequestCopies();

  final TokenManager<T> _manager;
  final Client _inner;
  final Map<String, String> Function(T tokens) _headers;
  final bool Function(BaseResponse response) _isAuthFailure;
  final bool Function(BaseRequest request) _shouldAuthorize;

  /// Sends [request] with valid tokens.
  ///
  /// Throws `NotAuthenticated`, `InvalidGrant` or `Transient` when the
  /// manager has no tokens to send; the request is then not sent.
  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    if (!_shouldAuthorize(request)) {
      return _inner.send(request);
    }
    return _sendOnce(request);
  }

  /// Sends [request] a single time; a rejection is returned as is and its
  /// tokens are reported, so the next request gets new ones.
  Future<StreamedResponse> _sendOnce(BaseRequest request) async {
    final tokens = await _manager.validToken();
    final response = await _inner.send(_authorized(request, tokens));
    if (_isAuthFailure(response)) {
      unawaited(_reportRejected(tokens));
    }
    return response;
  }

  /// Returns the copy of [request] that carries the headers of [tokens].
  BaseRequest _authorized(BaseRequest request, T tokens) {
    final headers = _headers(tokens);
    return switch (_copies.asReplayable(request)) {
      final Request replayable => _copies.copyOf(replayable, headers),
      null => _copies.streamOf(request, headers),
    };
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

  static Map<String, String> _bearer(Object? tokens) => switch (tokens) {
    TokenSet(:final accessToken) => {'Authorization': 'Bearer $accessToken'},
    _ => throw StateError('HttpTokenClient needs headers for this token type.'),
  };

  static bool _isUnauthorized(BaseResponse response) =>
      response.statusCode == _unauthorized;

  static bool _authorizesAll(BaseRequest request) => true;
}
