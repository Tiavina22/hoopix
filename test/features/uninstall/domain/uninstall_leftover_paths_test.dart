import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/uninstall/domain/entities/uninstall_leftover_paths.dart';

const _home = '/Users/tester';

void main() {
  test('generates the fixed app-name-keyed templates', () {
    final candidates = uninstallLeftoverPathCandidates(
      home: _home,
      bundleId: 'unknown',
      appName: 'MyApp',
    );

    expect(candidates, contains('$_home/Library/Application Support/MyApp'));
    expect(candidates, contains('$_home/Library/Caches/MyApp'));
    expect(candidates, contains('$_home/Library/Preferences/MyApp.plist'));
    expect(
      candidates,
      contains('$_home/Library/Saved Application State/MyApp.savedState'),
    );
    expect(candidates, contains('$_home/.config/MyApp'));
  });

  test(
    'generates bundle-id-keyed templates only for a valid reverse-DNS id',
    () {
      final valid = uninstallLeftoverPathCandidates(
        home: _home,
        bundleId: 'com.example.MyApp',
        appName: 'MyApp',
      );
      expect(valid, contains('$_home/Library/Containers/com.example.MyApp'));
      expect(
        valid,
        contains('$_home/Library/HTTPStorages/com.example.MyApp.binarycookies'),
      );

      final invalid = uninstallLeftoverPathCandidates(
        home: _home,
        bundleId: 'unknown',
        appName: 'MyApp',
      );
      expect(invalid, isNot(contains('$_home/Library/Containers/unknown')));
    },
  );

  test('generates compound-name variants only for a multi-word name', () {
    final compound = uninstallLeftoverPathCandidates(
      home: _home,
      bundleId: 'unknown',
      appName: 'Maestro Studio',
    );
    expect(
      compound,
      contains('$_home/Library/Application Support/MaestroStudio'),
    );
    expect(
      compound,
      contains('$_home/Library/Application Support/Maestro_Studio'),
    );
    expect(compound, contains('$_home/.cache/maestro-studio'));

    final singleWord = uninstallLeftoverPathCandidates(
      home: _home,
      bundleId: 'unknown',
      appName: 'Zed',
    );
    // The lowercase-hyphen .config variant only ever comes from the
    // compound-name pass, which a single-word name never triggers.
    expect(singleWord, isNot(contains('$_home/.config/zed-')));
    expect(
      singleWord.where((p) => p.contains('_')),
      isEmpty,
      reason: 'no underscore variant should exist for a single-word name',
    );
  });

  test('generates base-name variants for a versioned app name', () {
    final candidates = uninstallLeftoverPathCandidates(
      home: _home,
      bundleId: 'unknown',
      appName: 'Zed Nightly',
    );

    expect(candidates, contains('$_home/Library/Application Support/Zed'));
    expect(candidates, contains('$_home/.cache/zed'));
  });

  test('does not generate base-name variants for a non-versioned name', () {
    final candidates = uninstallLeftoverPathCandidates(
      home: _home,
      bundleId: 'unknown',
      appName: 'MyApp',
    );

    // "MyApp" has no version suffix, so base_name == app_name and no
    // separate base-name pass runs.
    expect(
      candidates.where((p) => p == '$_home/Library/Caches/MyApp'),
      hasLength(1),
    );
  });

  test('never proposes a bare generic Library root', () {
    // A pathological case: nothing should ever produce a bare root, but
    // the guard is defense in depth — assert it holds for every candidate.
    final candidates = uninstallLeftoverPathCandidates(
      home: _home,
      bundleId: 'com.example.MyApp',
      appName: 'MyApp',
    );

    const genericRoots = [
      '/Library/Application Support',
      '/Library/Caches',
      '/Library/Containers',
      '/.config',
      '/.cache',
      '/.local/share',
    ];
    for (final root in genericRoots) {
      expect(candidates, isNot(contains('$_home$root')));
    }
  });

  test('never proposes a shared XDG state root', () {
    // A pathologically short/edge-case name could otherwise collapse to
    // "$HOME/.config" or similar; the shared-root guard blocks it exactly
    // the way it blocks Clean's own leftover sweep.
    final candidates = uninstallLeftoverPathCandidates(
      home: _home,
      bundleId: 'unknown',
      appName: 'Local',
    );

    expect(candidates, isNot(contains('$_home/.config')));
    expect(candidates, isNot(contains('$_home/.cache')));
  });

  test('never proposes an independent CLI dotdir sharing the app name', () {
    final candidates = uninstallLeftoverPathCandidates(
      home: _home,
      bundleId: 'unknown',
      appName: 'claude',
    );

    expect(candidates, isNot(contains('$_home/.config/claude')));
  });

  test('generates nothing for too short an app name with no bundle id', () {
    final candidates = uninstallLeftoverPathCandidates(
      home: _home,
      bundleId: 'unknown',
      appName: 'A',
    );

    expect(candidates, isEmpty);
  });
}
