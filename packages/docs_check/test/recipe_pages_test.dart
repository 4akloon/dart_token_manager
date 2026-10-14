import 'dart:io';

import 'package:test/test.dart';

import 'helpers/banned_wording.dart';
import 'helpers/markdown_links.dart';
import 'helpers/recipe_includes.dart';
import 'helpers/repository_docs.dart';

void main() {
  final docs = RepositoryDocs();
  const links = MarkdownLinks();
  const includes = RecipeIncludes();
  const wording = BannedWording();

  test('every recipe page shows its code exactly as the compiled file', () {
    final failures = [
      for (final page in docs.recipePages)
        ...includes.failuresIn(page, docs.packageOf(page)),
    ];

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('every recipe page includes at least one file', () {
    final empty = [
      for (final page in docs.recipePages)
        if (includes.includedBy(page).isEmpty) page.path,
    ];

    expect(empty, isEmpty, reason: empty.join('\n'));
  });

  test('every recipe example is included by a page of its package', () {
    final included = {
      for (final page in docs.recipePages)
        for (final path in includes.includedBy(page))
          File.fromUri(docs.packageOf(page).uri.resolve(path)).absolute.path,
    };

    final orphans = [
      for (final example in docs.recipeExamples)
        if (!included.contains(example.absolute.path)) example.path,
    ];

    expect(orphans, isEmpty, reason: orphans.join('\n'));
  });

  test('a recipe page has no relative file link', () {
    // The API docs of pub.dev do not rewrite relative links, so a recipe page
    // links to other files by absolute URL.
    final offenders = [
      for (final page in docs.recipePages)
        for (final target in links.targetsIn(page.readAsStringSync()))
          if (!target.contains(':') && !target.startsWith('#'))
            '${page.path}: ($target)',
    ];

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('a recipe page compares approaches, never named products', () {
    final offenders = [
      for (final page in docs.recipePages)
        for (final phrase in wording.offendersIn(page.readAsStringSync()))
          '${page.path}: $phrase',
    ];

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
