import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/domain/entities/clean_whitelist.dart';
import 'package:hoopix/features/clean/domain/entities/whitelist_catalog.dart';
import 'package:hoopix/features/clean/domain/entities/whitelist_selection.dart';

const _home = '/Users/tester';

WhitelistCatalogItem item(String label) =>
    whitelistCatalog.firstWhere((item) => item.label == label);

WhitelistSelection load(List<String>? lines) =>
    WhitelistSelection.load(home: _home, fileLines: lines);

void main() {
  group('with no file yet', () {
    final selection = load(null);

    test('reads the convenience defaults, as Clean itself does', () {
      expect(selection.isDefault, isTrue);
      expect(selection.isChecked(item('Playwright browser binaries')), isTrue);
      expect(selection.isChecked(item('Ollama local AI models')), isTrue);
      expect(
        selection.isChecked(item('Gradle daemon processes cache')),
        isTrue,
      );
      expect(selection.isChecked(item('npm package cache')), isFalse);
    });

    test('keeps the defaults the catalog does not list as custom rows', () {
      expect(
        selection.custom,
        containsAll([
          '$_home/Library/Caches/JetBrains*',
          '$_home/Library/Mobile Documents*',
        ]),
      );
    });

    test('never lists a hard-safety rule as a custom row', () {
      expect(selection.custom, isNot(contains(finderMetadataSentinel)));
    });
  });

  group('reading a saved file', () {
    test('matches ~, \$HOME and \${HOME} to the same catalog row', () {
      for (final line in [
        '~/.npm/_cacache/*',
        r'$HOME/.npm/_cacache/*',
        r'${HOME}/.npm/_cacache/*',
        '$_home/.npm/_cacache/*',
      ]) {
        final selection = load([line]);
        expect(selection.isChecked(item('npm package cache')), isTrue);
        expect(selection.custom, isEmpty, reason: line);
      }
    });

    test('skips comments and blank lines, and collapses duplicates', () {
      final selection = load([
        '# a comment',
        '',
        '~/Work/keep/*',
        '$_home/Work/keep/*',
      ]);

      expect(selection.isDefault, isFalse);
      expect(selection.custom, ['~/Work/keep/*']);
    });

    test('an empty file means nothing chosen, not the defaults', () {
      final selection = load(const []);

      expect(selection.isDefault, isFalse);
      expect(selection.isChecked(item('Playwright browser binaries')), isFalse);
      expect(selection.custom, isEmpty);
    });
  });

  group('always-protected rows', () {
    final selection = load(const []);

    test('are checked and cannot be cleared', () {
      for (final label in [
        'Finder metadata, .DS_Store',
        'Font cache',
        'Spotlight metadata cache',
        'CloudKit cache',
      ]) {
        expect(selection.isAlwaysProtected(item(label)), isTrue, reason: label);
        expect(selection.isChecked(item(label)), isTrue, reason: label);
        expect(
          selection.toggled(item(label)).isChecked(item(label)),
          isTrue,
          reason: label,
        );
      }
    });

    test('ordinary rows are not', () {
      expect(selection.isAlwaysProtected(item('npm package cache')), isFalse);
      expect(selection.isAlwaysProtected(item('Trash')), isFalse);
    });
  });

  group('custom paths', () {
    test('are refused with the reason Clean would give', () {
      final selection = load(const []);

      expect(
        selection.withCustom('relative/path').refusal,
        'Must be absolute path',
      );
      expect(
        selection.withCustom('~/a/../b').refusal,
        'Path traversal not allowed',
      );
      expect(
        selection.withCustom('/System/Library').refusal,
        'Protected system path',
      );
    });

    test('one the catalog lists checks that row instead', () {
      final result = load(const []).withCustom('~/.cache/pip/*');

      expect(result.refusal, isNull);
      expect(
        result.selection.isChecked(item('pip Python package cache')),
        isTrue,
      );
      expect(result.selection.custom, isEmpty);
    });

    test('are added once and can be removed', () {
      final added = load(const [])
          .withCustom('~/Work/keep/*')
          .selection
          .withCustom('$_home/Work/keep/*')
          .selection;

      expect(added.custom, ['~/Work/keep/*']);
      expect(added.withoutCustom('~/Work/keep/*').custom, isEmpty);
    });
  });

  test('saves the checked rows in catalog order, then custom, and Clean '
      'protects exactly that', () {
    final selection = load(const [])
        .toggled(item('npm package cache'))
        .toggled(item('Homebrew downloaded packages'))
        .withCustom('~/Work/keep/*')
        .selection;

    final lines = selection.toFileLines();

    expect(lines.where((line) => !line.startsWith('#') && line.isNotEmpty), [
      '~/.npm/_cacache/*',
      '~/Library/Caches/Homebrew/*',
      '~/Work/keep/*',
    ]);

    final whitelist = CleanWhitelist.from(home: _home, userLines: lines);
    expect(whitelist.warnings, isEmpty);
    expect(whitelist.covers('$_home/.npm/_cacache/index-v5'), isTrue);
    expect(
      whitelist.covers('$_home/Library/Caches/Homebrew/downloads'),
      isTrue,
    );
    expect(whitelist.covers('$_home/Work/keep/build'), isTrue);
    expect(whitelist.covers('$_home/Library/Caches/Firefox/x'), isFalse);

    // And it reads back as the same choice.
    final reloaded = load(lines);
    expect(reloaded.isChecked(item('npm package cache')), isTrue);
    expect(reloaded.isChecked(item('Homebrew downloaded packages')), isTrue);
    expect(reloaded.custom, ['~/Work/keep/*']);
  });
}
