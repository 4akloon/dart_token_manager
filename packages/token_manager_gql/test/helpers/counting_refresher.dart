import 'package:token_manager/token_manager.dart';

/// A refresher that counts its calls and returns `fresh-<n>` on call `n`, or
/// throws [failure] when one is set.
final class CountingRefresher implements TokenRefresher<TokenSet> {
  /// Creates a refresher that succeeds, or always throws [failure].
  CountingRefresher({this.failure});

  /// What every call throws; `null` makes calls succeed.
  final Exception? failure;

  int _calls = 0;

  /// How many times [refresh] was called.
  int get calls => _calls;

  @override
  Future<TokenSet> refresh(TokenSet current) async {
    _calls++;
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    return TokenSet(accessToken: 'fresh-$_calls');
  }
}
