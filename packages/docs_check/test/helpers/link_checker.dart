import 'dart:io';

import 'markdown_links.dart';

/// Checks that the links of a page that point into this repository resolve.
///
/// A relative link is resolved from the page. An absolute link under
/// [blobPrefix] is resolved from the repository root. Every other absolute
/// link is not checked: the tests run without a network.
final class LinkChecker {
  /// Creates a checker for the repository at [root].
  const LinkChecker(this.root);

  /// The start of a GitHub link to a file of this repository on `main`.
  static const String blobPrefix =
      'https://github.com/4akloon/dart_token_manager/blob/main/';

  /// The repository root.
  final Directory root;

  static const MarkdownLinks _links = MarkdownLinks();

  /// The links of [page] that do not resolve, as readable messages.
  List<String> failuresIn(File page) {
    final text = page.readAsStringSync();
    final failures = <String>[];
    for (final target in _links.targetsIn(text)) {
      final problem = _problemWith(target, page, text);
      if (problem != null) {
        failures.add('${page.path}: ($target) $problem');
      }
    }
    return failures;
  }

  /// Why [target] does not resolve, or `null` when it does or is not checked.
  String? _problemWith(String target, File page, String text) {
    final hash = target.indexOf('#');
    final path = hash < 0 ? target : target.substring(0, hash);
    final anchor = hash < 0 ? null : target.substring(hash + 1);
    final file = _fileFor(path, page);
    if (file == null) {
      return null;
    }
    if (path.isEmpty) {
      return _missingAnchor(anchor, text);
    }
    if (FileSystemEntity.typeSync(file.path) == FileSystemEntityType.notFound) {
      return 'does not exist';
    }
    if (anchor != null && file.path.endsWith('.md') && file.existsSync()) {
      return _missingAnchor(anchor, file.readAsStringSync());
    }
    return null;
  }

  /// The local file [path] stands for, or `null` for a link not checked.
  File? _fileFor(String path, File page) {
    if (path.startsWith(blobPrefix)) {
      return File.fromUri(root.uri.resolve(path.substring(blobPrefix.length)));
    }
    if (path.contains(':')) {
      return null;
    }
    return File.fromUri(page.absolute.uri.resolve(path));
  }

  String? _missingAnchor(String? anchor, String text) {
    if (anchor == null || anchor.isEmpty) {
      return null;
    }
    return _links.anchorsIn(text).contains(anchor) ? null : 'has no heading';
  }
}
