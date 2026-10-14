import 'dart:async';

import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:token_manager/token_manager.dart';

import 'auth_failure_matcher.dart';
import 'skip_authorization.dart';

/// Attaches tokens to GraphQL requests and replays a request once after the
/// server rejects them.
///
/// The link never refreshes by itself: it asks the [TokenManager] for valid
/// tokens and reports the rejected ones, so concurrent requests share one
/// refresh. Put it right before the terminating link, after a `DedupeLink`,
/// and never combine it with graphql's `AuthLink`, which sets the same header
/// and cannot replay.
///
/// A rejection arrives as an error event that [AuthFailureMatcher.isAuthError]
/// accepts, or as a [Response] that [AuthFailureMatcher.isAuthResponse]
/// accepts and that has no `data`. A response with `data` is never replayed,
/// because a mutation may already have run. Only a rejection before the first
/// response is replayed, and only once; when the replay is rejected too, its
/// error or response is delivered as is.
///
/// ```dart
/// Link buildLink(TokenManager<TokenSet> manager) => Link.from([
///   DedupeLink(),
///   TokenManagerLink<TokenSet>(
///     manager: manager,
///     headers: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
///   ),
///   HttpLink('https://api.example.com/graphql'),
/// ]);
/// ```
///
/// {@category getting-started}
/// {@category clients}
final class TokenManagerLink<T> extends Link {
  /// Creates a link that sends the [headers] built from the [manager]'s tokens
  /// and recognises rejections with [matcher].
  ///
  /// The headers are merged into the `HttpLinkHeaders` the request already
  /// carries; on a clash the token header wins.
  TokenManagerLink({
    required TokenManager<T> manager,
    required Map<String, String> Function(T tokens) headers,
    AuthFailureMatcher matcher = const AuthFailureMatcher(),
  }) : _manager = manager,
       _headers = headers,
       _matcher = matcher;

  final TokenManager<T> _manager;
  final Map<String, String> Function(T tokens) _headers;
  final AuthFailureMatcher _matcher;

  /// Sends [request] through [forward] with valid tokens.
  ///
  /// A request marked with [SkipAuthorization] is forwarded unchanged. The
  /// manager's failures ([NotAuthenticated], [InvalidGrant], [Transient])
  /// arrive as error events, each wrapped in a [LinkException] whose
  /// `originalException` is the failure, not as exceptions of this method.
  /// Throws a [StateError] when [forward] is null: this link cannot terminate
  /// a chain.
  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    if (forward == null) {
      throw StateError(
        'TokenManagerLink cannot terminate a chain; put a terminating link '
        'such as HttpLink after it.',
      );
    }
    if (request.context.entry<SkipAuthorization>() != null) {
      return forward(request);
    }
    return _manager
        .authorizeStream<Response>(
          (tokens) => _send(request, tokens, forward),
          isAuthFailure: _isAuthFailure,
        )
        .transform(
          StreamTransformer<Response, Response>.fromHandlers(
            handleError: _deliverRejectedResponse,
          ),
        );
  }

  /// Sends a copy of [original] that carries the headers of [tokens]; every
  /// attempt starts from [original], never from an earlier attempt.
  Stream<Response> _send(Request original, T tokens, NextLink forward) {
    final authorized = original.updateContextEntry<HttpLinkHeaders>(
      (entry) => HttpLinkHeaders(
        headers: {...?entry?.headers, ..._headers(tokens)},
      ),
    );
    return forward(authorized).transform(
      StreamTransformer<Response, Response>.fromHandlers(
        handleData: _rejectUnauthenticated,
      ),
    );
  }

  /// Turns a rejected [response] without data into an error event, which is
  /// the only channel on which `authorizeStream` replays.
  void _rejectUnauthenticated(Response response, EventSink<Response> sink) {
    if (response.data == null && _matcher.isAuthResponse(response)) {
      sink.addError(_RejectedResponse(response));
    } else {
      sink.add(response);
    }
  }

  bool _isAuthFailure(Object error) =>
      error is _RejectedResponse || _matcher.isAuthError(error);

  /// Delivers a rejected response that was not replayed as the response it
  /// was, so the client sees the server's `errors` unchanged.
  void _deliverRejectedResponse(
    Object error,
    StackTrace stackTrace,
    EventSink<Response> sink,
  ) {
    if (error is _RejectedResponse) {
      sink.add(error.response);
    } else if (error is NotAuthenticated || error is RefreshFailure) {
      sink.addError(_ManagerFailureException(error, stackTrace), stackTrace);
    } else {
      sink.addError(error, stackTrace);
    }
  }
}

/// Wraps a failure of the manager so that GraphQL clients map it to a link
/// error; the failure stays reachable as `originalException`.
final class _ManagerFailureException extends LinkException {
  const _ManagerFailureException(
    Object super.originalException,
    StackTrace super.originalStackTrace,
  );

  @override
  String toString() => 'LinkException: $originalException';
}

/// Carries a rejected [Response] through the error channel of
/// `authorizeStream`; it never leaves [TokenManagerLink].
final class _RejectedResponse implements Exception {
  const _RejectedResponse(this.response);

  final Response response;
}
