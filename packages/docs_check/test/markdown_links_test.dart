import 'package:test/test.dart';

import 'helpers/markdown_links.dart';

void main() {
  const links = MarkdownLinks();

  test('targetsIn finds inline links with anchors', () {
    const text = 'See [a](doc/a.md#x) and [b](https://pub.dev/packages/b).';

    expect(links.targetsIn(text), ['doc/a.md#x', 'https://pub.dev/packages/b']);
  });

  test('targetsIn ignores fenced code and inline code', () {
    const text = '''
`[no](inline.md)`

```dart
// [no](fenced.md)
```

[yes](real.md)
''';

    expect(links.targetsIn(text), ['real.md']);
  });

  test('targetsIn ignores a link title', () {
    expect(links.targetsIn('[a](a.md "Title")'), ['a.md']);
  });

  test('slug follows the GitHub rule', () {
    expect(links.slug('Migrating from 0.1'), 'migrating-from-01');
    expect(links.slug('`TokenStore` and more'), 'tokenstore-and-more');
    expect(links.slug('Should I use this?'), 'should-i-use-this');
  });

  test('anchorsIn numbers a repeated heading', () {
    const text = '# One\n\n## Two\n\n## Two\n';

    expect(links.anchorsIn(text), {'one', 'two', 'two-1'});
  });

  test('anchorsIn skips a comment inside a fenced block', () {
    const text = '```sh\n# not a heading\n```\n\n# Real\n';

    expect(links.anchorsIn(text), {'real'});
  });
}
