import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:token_manager/token_manager.dart';

import 'auth_failure_matcher.dart';
import 'skip_authorization.dart';

/// Attaches tokens to GraphQL requests and replays a request once after the
/// server rejects them.
///
/// Put it right before the terminating link, after a `DedupeLink`:
/// `Link.from([DedupeLink(), TokenManagerLink(...), HttpLink(...)])`. Never
/// combine it with graphql's `AuthLink`. The link never refreshes by itself:
/// it asks the [TokenManager] for valid tokens and reports the rejected ones.
///
/// A rejection is an error event that [AuthFailureMatcher.isAuthError]
/// accepts. Only a rejection before the first response is replayed, and only
/// once; when the replay is rejected too, its error is delivered as is.
final class TokenManagerLink<T> extends Link {
  /// Creates a link that sends the [headers] built from the [manager]'s tokens
  /// and recognises rejections with [matcher].
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
  /// manager's failures (`NotAuthenticated`, `InvalidGrant`, `Transient`)
  /// arrive as error events. Throws a [StateError] when [forward] is null:
  /// this link cannot terminate a chain.
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
    return _manager.authorizeStream<Response>(
      (tokens) => _send(request, tokens, forward),
      isAuthFailure: _matcher.isAuthError,
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
    return forward(authorized);
  }
}
