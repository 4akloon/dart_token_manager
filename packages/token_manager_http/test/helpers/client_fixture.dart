import 'dart:async';

import 'package:http/http.dart';
import 'package:token_manager/token_manager.dart';
import 'package:token_manager_http/token_manager_http.dart';

import 'counting_refresher.dart';
import 'fake_answer.dart';
import 'recording_client.dart';
import 'sent_request.dart';

/// Wires an [HttpTokenClient] between a [TokenManager] and a
/// [RecordingClient], and builds requests for it.
final class ClientFixture {
  /// Creates a fixture whose session holds [old] when [isSignedIn], refreshes
  /// through a [CountingRefresher] when [hasRefresher] (which throws
  /// [refreshFailure] when it is set), and whose inner client answers with
  /// [answer]: by default 401 to the token `old` and 200 to any other.
  factory ClientFixture({
    bool isSignedIn = true,
    bool hasRefresher = true,
    Exception? refreshFailure,
    FutureOr<FakeAnswer> Function(SentRequest request)? answer,
  }) {
    final refresher = CountingRefresher(failure: refreshFailure);
    final manager = TokenManager<TokenSet>.create(
      store: InMemoryTokenStore<TokenSet>(isSignedIn ? old : null),
      refresher: hasRefresher ? refresher : null,
    );
    return ClientFixture._(manager, refresher, RecordingClient(answer: answer));
  }

  ClientFixture._(this.manager, this.refresher, this.inner)
    : client = HttpTokenClient<TokenSet>(manager: manager, inner: inner);

  /// The tokens a signed-in session starts with.
  static const TokenSet old = TokenSet(accessToken: 'old');

  /// The address of the test requests.
  static final Uri url = Uri.parse('https://api.example.com/me');

  /// The session's manager.
  final TokenManager<TokenSet> manager;

  /// The manager's refresher.
  final CountingRefresher refresher;

  /// The client behind [client].
  final RecordingClient inner;

  /// The client under test, with the default options.
  final HttpTokenClient<TokenSet> client;

  /// A client over the same [manager] and [inner] with the given options.
  HttpTokenClient<TokenSet> clientWith({
    Map<String, String> Function(TokenSet tokens)? headers,
    bool Function(BaseResponse response)? isAuthFailure,
    bool Function(BaseRequest request)? shouldAuthorize,
  }) => HttpTokenClient<TokenSet>(
    manager: manager,
    inner: inner,
    headers: headers,
    isAuthFailure: isAuthFailure,
    shouldAuthorize: shouldAuthorize,
  );

  /// A JSON POST to [url] with an `X-Trace` header.
  Request post() => Request('POST', url)
    ..headers['X-Trace'] = '1'
    ..headers['content-type'] = 'application/json'
    ..body = '{"name":"ada"}';
}
