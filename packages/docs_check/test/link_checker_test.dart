import 'dart:io';

import 'package:test/test.dart';

import 'helpers/link_checker.dart';

void main() {
  // Assigned in setUp, which runs before every test.
  late Directory root;
  late LinkChecker checker;

  File write(String path, String text) {
    final file = File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    return file;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('link_checker_test');
    checker = LinkChecker(root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('a relative link to an existing file resolves', () {
    write('docs/b.md', '# B\n');
    final page = write('docs/a.md', '[b](b.md)\n');

    expect(checker.failuresIn(page), isEmpty);
  });

  test('a relative link to a missing file fails', () {
    final page = write('docs/a.md', '[b](missing.md)\n');

    expect(checker.failuresIn(page), hasLength(1));
  });

  test('an anchor must name a heading of the target', () {
    write('docs/b.md', '# Real heading\n');
    final page = write(
      'docs/a.md',
      '[ok](b.md#real-heading) [bad](b.md#nope)\n',
    );

    expect(checker.failuresIn(page), hasLength(1));
  });

  test('an anchor in the same page must name a heading', () {
    final page = write('a.md', '# Top\n\n[ok](#top) [bad](#nope)\n');

    expect(checker.failuresIn(page), hasLength(1));
  });

  test('a GitHub blob link resolves from the repository root', () {
    write('docs/recipes.md', '# Recipes\n');
    final page = write(
      'llms.txt',
      '[ok](${LinkChecker.blobPrefix}docs/recipes.md) '
          '[bad](${LinkChecker.blobPrefix}docs/gone.md)\n',
    );

    expect(checker.failuresIn(page), hasLength(1));
  });

  test('another absolute link is not checked', () {
    final page = write('a.md', '[x](https://pub.dev/packages/dio)\n');

    expect(checker.failuresIn(page), isEmpty);
  });
}
