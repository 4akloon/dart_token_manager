import '../clock.dart';
import '../token_info.dart';

/// Decides whether tokens must be refreshed before they are handed out, or
/// should be refreshed in the background.
final class RefreshPolicy<T> {
  /// Creates a policy that refreshes [skew] before expiry as told by [info].
  ///
  /// With [refreshAhead] set, tokens that expire within it are also due for a
  /// background refresh. It must be greater than [skew], or an
  /// [ArgumentError] is thrown.
  RefreshPolicy({
    required Duration skew,
    required Clock clock,
    Duration? refreshAhead,
    TokenInfo<T>? info,
  }) : _skew = skew,
       _refreshAhead = refreshAhead,
       _clock = clock,
       _info = info {
    if (refreshAhead != null && refreshAhead <= skew) {
      throw ArgumentError.value(
        refreshAhead,
        'refreshAhead',
        'must be greater than skew ($skew)',
      );
    }
  }

  final Duration _skew;
  final Duration? _refreshAhead;
  final Clock _clock;
  final TokenInfo<T>? _info;

  /// The margin used when a caller names none: the refresh-ahead window when
  /// set, else the skew.
  Duration get window => _refreshAhead ?? _skew;

  /// Whether [tokens] must be refreshed first.
  ///
  /// True when [tokens] are the very [rejected] instance a server refused, or
  /// when they expire within the skew.
  bool needsRefresh(T tokens, T? rejected) {
    return identical(tokens, rejected) || isExpiring(tokens, _skew);
  }

  /// Whether [tokens] are due for a background refresh.
  ///
  /// Always false without a refresh-ahead window.
  bool needsAheadRefresh(T tokens) {
    final ahead = _refreshAhead;
    return ahead != null && isExpiring(tokens, ahead);
  }

  /// Whether [tokens] expire within [window] of now; never for tokens without
  /// an expiry.
  bool isExpiring(T tokens, Duration window) {
    final expiresAt = _info?.expiresAt(tokens);
    if (expiresAt == null) {
      return false;
    }
    return !_clock.now().add(window).isBefore(expiresAt);
  }
}
