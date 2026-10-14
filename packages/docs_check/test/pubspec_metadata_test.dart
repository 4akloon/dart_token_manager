import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'helpers/repository_docs.dart';

void main() {
  final docs = RepositoryDocs();
  // pub.dev: topics are 2-32 characters, lowercase letters, digits and
  // hyphens, start with a letter, end with a letter or digit, no `--`.
  final topic = RegExp(r'^[a-z](?:[a-z0-9]|-(?!-))*[a-z0-9]$');

  Map<String, Object?> pubspecOf(Directory package) {
    final yaml = loadYaml(
      File('${package.path}/pubspec.yaml').readAsStringSync(),
    );
    return switch (yaml) {
      final YamlMap map => {
        for (final entry in map.entries) '${entry.key}': entry.value,
      },
      _ => throw const FormatException('pubspec.yaml is not a map'),
    };
  }

  for (final package in docs.packages) {
    final name = package.path.split('/').last;

    group(name, () {
      final pubspec = pubspecOf(package);

      test('description is one sentence of 60 to 180 characters', () {
        final description = '${pubspec['description']}';

        expect(description.length, inInclusiveRange(60, 180));
        expect(description, endsWith('.'));
      });

      test('topics are at most five valid pub.dev topics', () {
        final topics = switch (pubspec['topics']) {
          final YamlList list => list.map((item) => '$item').toList(),
          _ => <String>[],
        };

        expect(topics, isNotEmpty);
        expect(topics.length, lessThanOrEqualTo(5));
        expect(topics.toSet(), hasLength(topics.length));
        for (final item in topics) {
          expect(item.length, inInclusiveRange(2, 32), reason: item);
          expect(topic.hasMatch(item), isTrue, reason: item);
        }
      });

      test('repository names the package folder, so README links resolve', () {
        expect(
          pubspec['repository'],
          'https://github.com/4akloon/dart_token_manager/tree/main/packages/$name',
        );
      });
    });
  }
}
