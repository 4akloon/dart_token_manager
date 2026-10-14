import '../clock.dart';
import '../token_info.dart';

/// Decides whether tokens must be refreshed before they are handed out.
final class RefreshPolicy<T> {
  /// Creates a policy that refreshes [skew] before expiry as told by [info].
  const RefreshPolicy({
    required Duration skew,
    required Clock clock,
    TokenInfo<T>? info,
  }) : _skew = skew,
       _clock = clock,
       _info = info;

  final Duration _skew;
  final Clock _clock;
  final TokenInfo<T>? _info;

  /// Whether [tokens] must be refreshed first.
  ///
  /// True when [tokens] are the very [rejected] instance a server refused, or
  /// when they expire within the skew.
  bool needsRefresh(T tokens, T? rejected) {
    return identical(tokens, rejected) || _isExpiring(tokens);
  }

  bool _isExpiring(T tokens) {
    final expiresAt = _info?.expiresAt(tokens);
    if (expiresAt == null) {
      return false;
    }
    return !_clock.now().add(_skew).isBefore(expiresAt);
  }
}
