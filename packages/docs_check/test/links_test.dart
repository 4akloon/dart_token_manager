import 'package:test/test.dart';

import 'helpers/link_checker.dart';
import 'helpers/markdown_links.dart';
import 'helpers/repository_docs.dart';

void main() {
  final docs = RepositoryDocs();
  const links = MarkdownLinks();

  test('every link into the repository resolves', () {
    final checker = LinkChecker(docs.root);

    final failures = [
      for (final page in docs.checkedPages) ...checker.failuresIn(page),
    ];

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('llms.txt links only by absolute URL', () {
    final offenders = [
      for (final target in links.targetsIn(docs.llms.readAsStringSync()))
        if (!target.startsWith('https://')) target,
    ];

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('docs/recipes.md lists every recipe page', () {
    final index = docs.recipeIndex.readAsStringSync();

    final missing = [
      for (final page in docs.recipePages)
        if (!index.contains(docs.relativePath(page))) page.path,
    ];

    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('llms.txt lists every recipe page and the recipe index', () {
    final llms = docs.llms.readAsStringSync();

    final missing = [
      for (final page in docs.recipePages)
        if (!llms.contains(
          '${LinkChecker.blobPrefix}${docs.relativePath(page)}',
        ))
          page.path,
      if (!llms.contains('${LinkChecker.blobPrefix}docs/recipes.md'))
        'docs/recipes.md',
    ];

    expect(missing, isEmpty, reason: missing.join('\n'));
  });
}
