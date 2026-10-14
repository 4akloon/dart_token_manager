/// A gql_link `Link` that attaches token_manager tokens to GraphQL requests
/// and replays a request once after an auth failure.
///
/// It depends only on `gql_link`, `gql_exec` and `token_manager`, so it works
/// with every client built on `gql_link`, such as `graphql`, `graphql_flutter`
/// and `ferry`.
///
/// {@category getting-started}
library;

export 'src/auth_failure_matcher.dart' show AuthFailureMatcher;
export 'src/skip_authorization.dart' show SkipAuthorization;
export 'src/token_manager_link.dart' show TokenManagerLink;
export 'src/token_manager_socket_auth.dart' show TokenManagerSocketAuth;
