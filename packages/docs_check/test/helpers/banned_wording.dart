/// Finds wording that compares this project with other packages.
///
/// The docs compare approaches (a hand-written interceptor), never products:
/// a claim about a named third-party package cannot be verified here and goes
/// stale.
final class BannedWording {
  /// Creates the finder.
  const BannedWording();

  static final RegExp _comparison = RegExp(
    r'\b(?:better|faster|safer|simpler|cleaner) than\b|\bunlike\b|'
    r'\bcompared (?:to|with)\b|\balternatives? to\b|\bvs\.?(?=\s)',
    caseSensitive: false,
  );

  /// The comparing phrases in [text], in order.
  List<String> offendersIn(String text) {
    return [for (final match in _comparison.allMatches(text)) match[0] ?? ''];
  }
}
