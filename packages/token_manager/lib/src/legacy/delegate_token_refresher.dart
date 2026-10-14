// The legacy adapters implement the deprecated API on purpose.
// ignore_for_file: deprecated_member_use_from_same_package

import '../refresh_failure.dart';
import '../revoked_tokens_exception.dart';
import '../token_manager_refresh_delegate.dart';
import '../token_refresher.dart';

/// Adapts the old refresh delegate to a [TokenRefresher].
final class DelegateTokenRefresher<T> implements TokenRefresher<T> {
  /// Creates a refresher over [delegate].
  const DelegateTokenRefresher(this._delegate);

  final TokenManagerRefreshDelegate<T> _delegate;

  @override
  Future<T> refresh(T current) async {
    try {
      return await _delegate.refresh(current);
    } on RevokedTokensException {
      throw const InvalidGrant();
    }
  }
}
