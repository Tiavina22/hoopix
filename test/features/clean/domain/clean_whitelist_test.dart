import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/domain/entities/clean_whitelist.dart';

const _home = '/Users/tester';

CleanWhitelist build([List<String>? lines]) =>
    CleanWhitelist.from(home: _home, userLines: lines);

void main() {
  group('safety patterns', () {
    test('a custom whitelist still gets the hard safety rows', () {
      // The #1396 case: replacing the defaults must not drop these.
      final whitelist = build(['$_home/Library/Caches/mine']);

      expect(whitelist.covers('$_home/Library/Caches/mine'), isTrue);
      expect(whitelist.covers('$_home/Library/Caches/CloudKit'), isTrue);
      expect(whitelist.covers('$_home/Library/Caches/com.apple.Spotlight'), isTrue);
      expect(
        whitelist.covers('$_home/Library/Caches/pypoetry/virtualenvs/proj'),
        isTrue,
      );
    });

    test('an empty saved file still keeps the safety rows', () {
      final whitelist = build([]);

      expect(whitelist.covers('$_home/Library/Caches/CloudKit'), isTrue);
      // But the replaceable convenience defaults are gone.
      expect(whitelist.covers('$_home/.gradle/caches/modules'), isFalse);
    });

    test('without a saved file the convenience defaults apply', () {
      final whitelist = build();

      expect(whitelist.covers('$_home/.gradle/caches/modules'), isTrue);
      expect(whitelist.covers('$_home/Library/Caches/JetBrains2024'), isTrue);
    });
  });

  group('matching', () {
    test('covers an exact path', () {
      expect(build(['$_home/keep']).covers('$_home/keep'), isTrue);
    });

    test('covers a glob', () {
      final whitelist = build(['$_home/Library/Caches/Foo*']);

      expect(whitelist.covers('$_home/Library/Caches/Foobar'), isTrue);
      expect(whitelist.covers('$_home/Library/Caches/Bar'), isFalse);
    });

    test('protects a parent whose child is whitelisted', () {
      // Deleting the parent would take the whitelisted child with it.
      final whitelist = build(['$_home/Projects/keep/data']);

      expect(whitelist.covers('$_home/Projects/keep'), isTrue);
      expect(whitelist.covers('$_home/Projects'), isTrue);
    });

    test('protects children of a whitelisted literal directory', () {
      final whitelist = build(['$_home/Projects/keep']);

      expect(whitelist.covers('$_home/Projects/keep/nested/file'), isTrue);
    });

    test('a glob pattern does not protect children by prefix', () {
      // "Foo*" is a pattern, not a directory, so its textual prefix must not
      // be treated as one.
      final whitelist = build(['$_home/Library/Caches/Foo*']);

      expect(whitelist.covers('$_home/Library/Caches/Foo/child'), isTrue);
      expect(whitelist.covers('$_home/Library/Cach'), isFalse);
    });

    test('normalizes trailing and doubled separators', () {
      final whitelist = build(['$_home/keep/']);

      expect(whitelist.covers('$_home/keep'), isTrue);
      expect(whitelist.covers('$_home//keep'), isTrue);
    });

    test('an unrelated path is not covered', () {
      expect(build(['$_home/keep']).covers('$_home/other'), isFalse);
    });
  });

  group('parsing', () {
    test('expands ~ and \$HOME', () {
      final whitelist = build([r'~/keep-tilde', r'$HOME/keep-var', r'${HOME}/keep-brace']);

      expect(whitelist.covers('$_home/keep-tilde'), isTrue);
      expect(whitelist.covers('$_home/keep-var'), isTrue);
      expect(whitelist.covers('$_home/keep-brace'), isTrue);
    });

    test('skips comments and blank lines', () {
      final whitelist = build(['# a comment', '', '   ', '$_home/keep']);

      expect(whitelist.patterns, contains('$_home/keep'));
      expect(whitelist.warnings, isEmpty);
    });

    test('refuses traversal, relative paths and doubled slashes, and says why', () {
      final whitelist = build([
        '$_home/../etc/passwd',
        'relative/path',
        '$_home//doubled',
      ]);

      // The safety rows are always present, so the check is that none of the
      // refused lines got through — not that the list is empty.
      expect(whitelist.covers('/etc/passwd'), isFalse);
      expect(whitelist.patterns.any((p) => p.contains('relative')), isFalse);
      expect(whitelist.patterns.any((p) => p.contains('doubled')), isFalse);
      expect(
        whitelist.warnings.map((w) => w.reason),
        containsAll([
          'Path traversal not allowed',
          'Must be absolute path',
          'Consecutive slashes',
        ]),
      );
    });

    test('refuses system paths, which whitelisting cannot help', () {
      final whitelist = build(['/System/Library', '/', '/usr/bin/env']);

      expect(whitelist.patterns.any((p) => p.startsWith('/System')), isFalse);
      expect(whitelist.patterns.any((p) => p.startsWith('/usr/bin')), isFalse);
      expect(whitelist.warnings, hasLength(3));
      expect(
        whitelist.warnings.every((w) => w.reason == 'Protected system path'),
        isTrue,
      );
    });
  });

  group('the Finder metadata sentinel', () {
    test('is a flag, not a path to match', () {
      final whitelist = build([finderMetadataSentinel, '$_home/keep']);

      expect(whitelist.protectsFinderMetadata, isTrue);
      expect(whitelist.patterns, isNot(contains(finderMetadataSentinel)));
      expect(whitelist.covers(finderMetadataSentinel), isFalse);
    });

    test('is on by default, because safety merges it', () {
      expect(build(['$_home/keep']).protectsFinderMetadata, isTrue);
    });
  });
}
