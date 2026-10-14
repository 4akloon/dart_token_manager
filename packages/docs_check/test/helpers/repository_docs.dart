import 'dart:io';

/// Locates the documents the checks read; the tests run in
/// `packages/docs_check`.
final class RepositoryDocs {
  /// Creates the locator for the repository that contains the working
  /// directory's `packages/` folder.
  RepositoryDocs() : root = Directory.current.parent.parent;

  /// The repository root.
  final Directory root;

  /// `llms.txt` at the repository root.
  File get llms => File('${root.path}/llms.txt');

  /// The recipe index, `docs/recipes.md`.
  File get recipeIndex => File('${root.path}/docs/recipes.md');

  /// The publishable packages (every package but this one).
  List<Directory> get packages {
    final directories =
        Directory('${root.path}/packages')
            .listSync()
            .whereType<Directory>()
            .where((dir) => !dir.path.endsWith('/docs_check'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return directories;
  }

  /// The README of every package and the root README.
  List<File> get readmes => [
    File('${root.path}/README.md'),
    for (final package in packages) File('${package.path}/README.md'),
  ];

  /// Every `doc/recipes/*.md` of every package.
  List<File> get recipePages => [
    for (final package in packages)
      ..._files('${package.path}/doc/recipes', '.md'),
  ];

  /// Every `example/recipes/*.dart` of every package.
  List<File> get recipeExamples => [
    for (final package in packages)
      ..._files('${package.path}/example/recipes', '.dart'),
  ];

  /// Every page whose links are checked.
  List<File> get checkedPages => [
    ...readmes,
    ...recipePages,
    recipeIndex,
    llms,
  ];

  /// The package directory that owns [file].
  Directory packageOf(File file) {
    var directory = file.absolute.parent;
    while (!File('${directory.path}/pubspec.yaml').existsSync()) {
      directory = directory.parent;
    }
    return directory;
  }

  /// The path of [file] from the repository root.
  String relativePath(File file) {
    return file.absolute.path.substring(root.absolute.path.length + 1);
  }

  List<File> _files(String directory, String extension) {
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      return const [];
    }
    return dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith(extension))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }
}
