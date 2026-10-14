import 'dart:io';

import 'package:test/test.dart';

import 'helpers/banned_wording.dart';
import 'helpers/repository_docs.dart';

void main() {
  final docs = RepositoryDocs();
  const wording = BannedWording();
  // What a coding agent searches for: one phrase the first sentence of each
  // README must contain.
  const searchPhrase = {
    'token_manager': 'refresh token',
    'token_manager_dio': 'refresh token interceptor',
    'token_manager_http': 'bearer token authorization and refresh on 401',
    'token_manager_grpc': 'auth token interceptor',
    'token_manager_gql': 'auth token',
  };

  String readmeOf(String package) {
    return File(
      '${docs.root.path}/packages/$package/README.md',
    ).readAsStringSync();
  }

  String blockOf(String readme) {
    final start = readme.indexOf('\n## Should I use this?\n');
    if (start < 0) {
      return '';
    }
    return readme.substring(start, readme.indexOf('\n## ', start + 1));
  }

  for (final MapEntry(key: package, value: phrase) in searchPhrase.entries) {
    group(package, () {
      final readme = readmeOf(package);

      test('has the "Should I use this?" block after Install', () {
        expect(
          readme.indexOf('\n## Should I use this?\n'),
          greaterThan(readme.indexOf('\n## Install\n')),
        );
        expect(readme, contains('- [Should I use this?](#should-i-use-this)'));
      });

      test('the block answers use it, do not need it, replaces, which', () {
        final block = blockOf(readme);

        expect(block, contains('- **Use it when:**'));
        expect(block, contains('- **You do not need it when:**'));
        expect(block, contains('- **What it replaces:**'));
        expect(block, contains('- **Which package:**'));
        for (final other in searchPhrase.keys) {
          expect(block, contains('https://pub.dev/packages/$other)'));
        }
      });

      test('the first sentence uses the words of the search queries', () {
        final first = readme
            .split('\n')
            .firstWhere(
              (line) => line.startsWith('**'),
            );

        expect(first.toLowerCase(), contains(phrase));
      });

      test('compares approaches, never named products', () {
        expect(wording.offendersIn(blockOf(readme)), isEmpty);
      });

      test('links outside the package folder are absolute', () {
        expect(readme, isNot(contains('](../')));
      });
    });
  }
}
