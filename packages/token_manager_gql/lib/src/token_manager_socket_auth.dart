import 'package:token_manager/token_manager.dart';

/// Supplies tokens to a GraphQL WebSocket client and refreshes them when the
/// server closes the socket for an auth reason.
///
/// A WebSocket link ignores the headers that `TokenManagerLink` sets, so a
/// subscription needs its own way to carry tokens. This class knows no client:
/// pass [initialPayload] as the `initialPayload` (or `connectionParams`)
/// callback and [onConnectionLost] as the `onConnectionLost` callback of the
/// client's config. The app still has to reconnect when tokens expire on a
/// live socket, close the socket on logout, and stop the client from retrying
/// while the user is signed out.
///
/// ```dart
/// final socketAuth = TokenManagerSocketAuth<TokenSet>(
///   manager: manager,
///   payload: (tokens) => {'Authorization': 'Bearer ${tokens.accessToken}'},
/// );
/// final webSocketLink = WebSocketLink(
///   'wss://api.example.com/graphql',
///   config: SocketClientConfig(
///     initialPayload: socketAuth.initialPayload,
///     onConnectionLost: socketAuth.onConnectionLost,
///   ),
/// );
/// ```
///
/// {@category subscriptions}
final class TokenManagerSocketAuth<T> {
  /// Creates the callbacks for [manager]; [payload] builds the connection
  /// payload from the tokens, and a close code in [authCloseCodes] means the
  /// server rejected them.
  ///
  /// WebSockets have no standard auth close code, so set [authCloseCodes] to
  /// what your server sends; the default is 4401, which graphql-ws uses.
  TokenManagerSocketAuth({
    required TokenManager<T> manager,
    required Map<String, Object?> Function(T tokens) payload,
    Set<int> authCloseCodes = const {4401},
  }) : _manager = manager,
       _payload = payload,
       _authCloseCodes = authCloseCodes;

  final TokenManager<T> _manager;
  final Map<String, Object?> Function(T tokens) _payload;
  final Set<int> _authCloseCodes;

  /// The tokens of the last payload, which the open socket was authorised
  /// with.
  T? _used;

  /// Returns the connection payload built from valid tokens.
  ///
  /// Throws what [TokenManager.validToken] throws: [NotAuthenticated],
  /// [InvalidGrant] or [Transient].
  Future<Map<String, Object?>> initialPayload() async {
    final tokens = await _manager.validToken();
    _used = tokens;
    return _payload(tokens);
  }

  /// Refreshes the tokens when [code] is an auth close code and returns the
  /// delay before the client reconnects.
  ///
  /// Returns [Duration.zero] after a refresh so the client reconnects at
  /// once, and `null` (the client's default delay) for any other close or when
  /// the refresh fails. It never throws an [Exception]: the client calls it
  /// from a reconnect loop that does not handle errors.
  Future<Duration?> onConnectionLost(int? code, String? reason) async {
    final used = _used;
    if (used == null || !_authCloseCodes.contains(code)) {
      return null;
    }
    try {
      await _manager.validToken(rejected: used);
      return Duration.zero;
    } on Exception catch (_) {
      // `initialPayload` reports the failure on the next connect.
      return null;
    }
  }
}
