/// Finds the links and the heading anchors of a Markdown text.
///
/// Fenced code blocks and inline code are ignored, so a link written as an
/// example in a recipe is not checked.
final class MarkdownLinks {
  /// Creates the reader.
  const MarkdownLinks();

  static final RegExp _fence = RegExp(r'^\s*(```|~~~)');
  static final RegExp _inlineCode = RegExp('`[^`]*`');
  static final RegExp _link = RegExp(r'\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)');
  static final RegExp _heading = RegExp(r'^#{1,6}\s+(.*?)\s*#*\s*$');
  static final RegExp _dropped = RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true);

  /// The targets of the inline links in [markdown], in order.
  List<String> targetsIn(String markdown) {
    final targets = <String>[];
    for (final line in _prose(markdown)) {
      for (final match in _link.allMatches(line)) {
        if (match.group(1) case final String target) {
          targets.add(target);
        }
      }
    }
    return targets;
  }

  /// The anchors GitHub generates for the headings of [markdown].
  Set<String> anchorsIn(String markdown) {
    final anchors = <String>{};
    final seen = <String, int>{};
    for (final line in _prose(markdown)) {
      final match = _heading.firstMatch(line);
      if (match?.group(1) case final String text) {
        final base = slug(text);
        final count = seen[base] ?? 0;
        seen[base] = count + 1;
        anchors.add(count == 0 ? base : '$base-$count');
      }
    }
    return anchors;
  }

  /// The GitHub anchor of the heading [text].
  String slug(String text) {
    return text
        .replaceAll('`', '')
        .toLowerCase()
        .replaceAll(_dropped, '')
        .trim()
        .replaceAll(' ', '-');
  }

  /// The lines outside fenced code blocks, without inline code.
  Iterable<String> _prose(String markdown) sync* {
    var isFenced = false;
    for (final line in markdown.split('\n')) {
      if (_fence.hasMatch(line)) {
        isFenced = !isFenced;
      } else if (!isFenced) {
        yield line.replaceAll(_inlineCode, '');
      }
    }
  }
}
