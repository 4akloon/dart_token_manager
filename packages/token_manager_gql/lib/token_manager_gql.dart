/// A gql_link `Link` that attaches token_manager tokens to GraphQL requests
/// and replays a request once after an auth failure.
library;

export 'src/auth_failure_matcher.dart' show AuthFailureMatcher;
