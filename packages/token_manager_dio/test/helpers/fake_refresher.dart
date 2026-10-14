import 'package:token_manager/token_manager.dart';

/// A refresher that counts its calls and returns the `new` access token, or
/// fails with [failure].
final class FakeRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher, optionally failing with [failure].
  FakeRefresher({this.failure});

  /// What every call throws; `null` makes calls succeed.
  final RefreshFailure? failure;

  /// How many times [refresh] was called.
  int calls = 0;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    calls++;
    // Let concurrent requests reach the manager while the refresh runs.
    await Future<void>.delayed(Duration.zero);
    final error = failure;
    if (error != null) {
      throw error;
    }
    return const TokenSet(accessToken: 'new', refreshToken: 'refresh-2');
  }
}
