import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/purge_search_roots.dart';

const _home = '/Users/tester';

void main() {
  group('configuredPurgeRoots', () {
    test('expands ~, drops comments, trailing slashes and repeats', () {
      expect(
        configuredPurgeRoots([
          '# Hoopix Purge Paths',
          '',
          '  ~/Work/ClientA/ ',
          '$_home/Work/ClientA',
          '/Volumes/Dev/src',
        ], home: _home),
        ['$_home/Work/ClientA', '/Volumes/Dev/src'],
      );
    });

    test('no file and a header-only file both mean no folders', () {
      expect(configuredPurgeRoots(null, home: _home), isEmpty);
      expect(
        configuredPurgeRoots(
          purgePathsFileLines(const [], home: _home),
          home: _home,
        ),
        isEmpty,
      );
    });
  });

  group('purgeScanRoots', () {
    test('configured folders replace discovery entirely', () {
      var discovered = false;
      final roots = purgeScanRoots(
        ['~/deep/nested/projects'],
        home: _home,
        discover: () {
          discovered = true;
          return ['$_home/Code'];
        },
      );

      expect(roots, ['$_home/deep/nested/projects']);
      expect(discovered, isFalse);
    });

    test('without configured folders, discovery decides', () {
      expect(
        purgeScanRoots(null, home: _home, discover: () => ['$_home/Code']),
        ['$_home/Code'],
      );
    });
  });

  test('purgeRootRefusal rejects what cannot name one real place', () {
    expect(
      purgeRootRefusal('relative/dir', home: _home),
      'Must be absolute path',
    );
    expect(
      purgeRootRefusal('~/Work/../..', home: _home),
      'Path traversal not allowed',
    );
    expect(purgeRootRefusal('/', home: _home), 'Whole disk not allowed');
    expect(purgeRootRefusal('~/Work', home: _home), isNull);
    expect(purgeRootRefusal('/Volumes/Dev/src', home: _home), isNull);
  });

  test('purgePathsFileLines writes home as ~ under a header', () {
    final lines = purgePathsFileLines([
      '$_home/Work',
      '/Volumes/Dev/src',
    ], home: _home);

    expect(lines.first, startsWith('#'));
    expect(lines.where((l) => !l.startsWith('#') && l.isNotEmpty), [
      '~/Work',
      '/Volumes/Dev/src',
    ]);
  });

  group('PurgeRootsSelection', () {
    PurgeRootsSelection load(List<String>? lines) => PurgeRootsSelection.load(
      home: _home,
      fileLines: lines,
      discovered: ['$_home/Code', '$_home/Projects'],
    );

    test('with nothing configured, shows discovery and saves no folder', () {
      final selection = load(null);

      expect(selection.isAutomatic, isTrue);
      expect(selection.roots, ['$_home/Code', '$_home/Projects']);
      expect(
        configuredPurgeRoots(selection.toFileLines(), home: _home),
        isEmpty,
      );
    });

    test('adding a folder switches to the user list, keeping the rest', () {
      final result = load(null).withRoot('~/Work/ClientA');

      expect(result.refusal, isNull);
      expect(result.selection.isAutomatic, isFalse);
      expect(
        configuredPurgeRoots(result.selection.toFileLines(), home: _home),
        ['$_home/Code', '$_home/Projects', '$_home/Work/ClientA'],
      );
    });

    test('a refused folder changes nothing', () {
      final result = load(null).withRoot('/');

      expect(result.refusal, 'Whole disk not allowed');
      expect(result.selection.isAutomatic, isTrue);
    });

    test('removing a folder switches to the user list too', () {
      final selection = load(null).withoutRoot('$_home/Projects');

      expect(selection.isAutomatic, isFalse);
      expect(selection.roots, ['$_home/Code']);
    });

    test('a saved list reads back as the same list', () {
      final selection = load(['~/Work']);

      expect(selection.isAutomatic, isFalse);
      expect(selection.roots, ['$_home/Work']);
    });

    test('going back to automatic restores discovery', () {
      final selection = load(['~/Work']).automatic();

      expect(selection.isAutomatic, isTrue);
      expect(selection.roots, ['$_home/Code', '$_home/Projects']);
      expect(
        configuredPurgeRoots(selection.toFileLines(), home: _home),
        isEmpty,
      );
    });
  });
}
