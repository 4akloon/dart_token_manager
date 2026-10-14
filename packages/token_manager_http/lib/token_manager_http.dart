/// A `package:http` client that attaches token_manager tokens to requests and
/// replays a request once after an auth failure.
///
/// {@category getting-started}
library;

export 'src/http_token_client.dart' show HttpTokenClient;
