# Auth Failures

`AuthFailureMatcher` decides whether a GraphQL failure means the server
rejected the tokens. `TokenManagerLink` replays a request only when it says so.

## Two channels

A server reports a rejection in one of two ways:

| Channel | Default rule |
|---|---|
| An error event, such as `HttpLink`'s `HttpLinkServerException` | a `ServerException` whose `statusCode` is 401 |
| A response whose `errors` carry an auth code (often an HTTP 200) | `errors[].extensions.code` is `UNAUTHENTICATED` |

`isAuthError` checks the first, `isAuthResponse` the second. Set other codes in
the constructor:

```dart
import 'package:token_manager_gql/token_manager_gql.dart';

const matcher = AuthFailureMatcher(
  statusCodes: {401, 419},
  errorCodes: {'invalid-jwt'},
);
```

Pass it to the link as `matcher:`. The defaults are replaced, not extended: with
`statusCodes: {419}` a 401 is no longer an auth failure.

## When a rejection is replayed

- A rejected **error event** is replayed.
- A rejected **response is replayed only when its `data` is null.** A response
  with data may come from a mutation that already ran, so it is delivered as is.
- Only a rejection before the first response is replayed. After a response, a
  401 is delivered unreplayed.
- A request is replayed **once**. When the replay is rejected too, its error or
  response reaches the client unchanged.
- Every attempt starts from the original request, never from an earlier attempt.

A rejected response that is not replayed (it had data, or it was the second
rejection) is delivered as the response it was, so the client sees the server's
`errors` unchanged.

## A 401 that is not GraphQL JSON

`HttpLink` parses the body before it checks the status. A 401 whose body is not
GraphQL JSON (empty, HTML) arrives as an `HttpLinkParserException`, which has no
status code, so the default matcher does not recognise it. Extend the matcher
in your app, which already depends on `gql_http_link`:

```dart
import 'package:gql_http_link/gql_http_link.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

final class AppAuthFailureMatcher extends AuthFailureMatcher {
  const AppAuthFailureMatcher();

  @override
  bool isAuthError(Object error) =>
      (error is HttpLinkParserException && error.response.statusCode == 401) ||
      super.isAuthError(error);
}
```

The same applies to a 403 whose body carries `UNAUTHENTICATED` and arrives as a
server exception: its status is not in `statusCodes`, so it is never replayed
until you override `isAuthError`.

## Operations without tokens

A login or sign-up runs before tokens exist. A request whose context holds
`SkipAuthorization` is forwarded unchanged: no header, no call to the manager,
no replay.

```dart
import 'package:gql_exec/gql_exec.dart';
import 'package:token_manager_gql/token_manager_gql.dart';

Request anonymous(Request request) =>
    request.withContextEntry(const SkipAuthorization());
```

With `graphql`, put the entry in the operation's context:
`Context().withEntry(const SkipAuthorization())`. Without the marker, a request
sent while signed out fails with `NotAuthenticated`.

## Errors from the manager

The manager's failures reach the client as error events, not as
`LinkException`s:

- `NotAuthenticated` — there is no session; the request is not sent.
- `InvalidGrant` — the session ended and the manager signed out.
- `Transient` — the refresh may succeed later; the session stays.

Listen to `manager.states` to send the user to sign-in on `Unauthenticated`.
