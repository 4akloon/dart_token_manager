import 'dart:io';

/// Checks that a recipe page shows its code exactly as the compiled file.
///
/// A page marks an included file with a comment line, directly followed by a
/// `dart` fenced block that holds the file:
///
/// ```text
/// <!-- include: example/recipes/name.dart -->
/// ```
///
/// The path is relative to the package that owns the page.
final class RecipeIncludes {
  /// Creates the checker.
  const RecipeIncludes();

  static final RegExp _marker = RegExp(r'^<!-- include: (\S+) -->$');

  /// The paths [page] includes, relative to its package.
  List<String> includedBy(File page) {
    return [
      for (final line in page.readAsLinesSync())
        if (_marker.firstMatch(line)?.group(1) case final String path) path,
    ];
  }

  /// The includes of [page] that differ from their file, as messages.
  List<String> failuresIn(File page, Directory packageRoot) {
    final lines = page.readAsLinesSync();
    final failures = <String>[];
    for (var index = 0; index < lines.length; index++) {
      if (_marker.firstMatch(lines[index])?.group(1) case final String path) {
        final problem = _problemWith(path, lines, index + 1, packageRoot);
        if (problem != null) {
          failures.add('${page.path}: include $path $problem');
        }
      }
    }
    return failures;
  }

  String? _problemWith(
    String path,
    List<String> lines,
    int fenceIndex,
    Directory packageRoot,
  ) {
    final file = File.fromUri(packageRoot.absolute.uri.resolve(path));
    if (!file.existsSync()) {
      return 'names a file that does not exist';
    }
    if (fenceIndex >= lines.length || lines[fenceIndex] != '```dart') {
      return 'is not followed by a ```dart block';
    }
    final shown = <String>[];
    for (var i = fenceIndex + 1; i < lines.length && lines[i] != '```'; i++) {
      shown.add(lines[i]);
    }
    return shown.join('\n') == file.readAsStringSync().trimRight()
        ? null
        : 'differs from the file; paste the file again';
  }
}
