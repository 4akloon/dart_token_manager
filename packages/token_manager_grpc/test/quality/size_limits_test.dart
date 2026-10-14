/// The size limits of `CLAUDE.md` ("Code quality rules") as a ratchet.
///
/// A file in `lib/` has at most 300 lines, a test file 500, a method 40. A
/// unit over its limit may only be listed below with the size it had when it
/// was listed, and it may only shrink. Never add a new entry, split the unit
/// instead.
library;

import 'package:test/test.dart';

import '../helpers/size_limits.dart';

/// Files over their limit with the lines (`wc -l`) they had when listed.
const Map<String, int> _fileAllowlist = {};

/// Files that are exempt for good: flat catalogs with no logic.
const Set<String> _permanent = {};

/// Methods over 40 lines (`path#Type.name`) with the lines they had.
const Map<String, int> _methodAllowlist = {};

void main() {
  final limits = SizeLimits('.');

  test('no file is over its size limit unless it is allowlisted', () {
    final failures = limits.fileFailures(
      allowlist: _fileAllowlist,
      permanent: _permanent,
    );
    if (failures.isNotEmpty) {
      fail(failures.join('\n'));
    }
  });

  test('no method is over 40 lines unless it is allowlisted', () {
    final failures = limits.methodFailures(allowlist: _methodAllowlist);
    if (failures.isNotEmpty) {
      fail(failures.join('\n'));
    }
  });
}
