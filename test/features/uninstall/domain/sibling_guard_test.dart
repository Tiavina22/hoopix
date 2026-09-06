import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/entities/sibling_guard.dart';

const _xcode = InstalledApp(
  path: '/Applications/Xcode.app',
  bundleId: 'com.apple.dt.Xcode',
  displayName: 'Xcode',
);
const _xcodeBeta = InstalledApp(
  path: '/Applications/Xcode-beta.app',
  bundleId: 'com.apple.dt.Xcode',
  displayName: 'Xcode-beta',
);
const _iterm2 = InstalledApp(
  path: '/Applications/iTerm.app',
  bundleId: 'com.googlecode.iterm2',
  displayName: 'iTerm2',
);
// A version-suffixed basename ("iTerm2 Beta") that strips down to exactly
// _iterm2's own display name ("iTerm2") — the collision
// siblingGuardLevelFor must catch, matching Mole's own comment that
// iterm2/iterm2-beta both share bundle id com.googlecode.iterm2.
const _iterm2Beta = InstalledApp(
  path: '/Applications/iTerm2 Beta.app',
  bundleId: 'com.googlecode.iterm2',
  displayName: 'iTerm2 Beta',
);

void main() {
  group('bundleIdHasSurvivingSibling', () {
    test('true when another app shares the bundle id and is not selected', () {
      final result = bundleIdHasSurvivingSibling(
        bundleId: _xcode.bundleId,
        appPath: _xcode.path,
        allApps: [_xcode, _xcodeBeta],
        selectedPaths: {_xcode.path},
      );

      expect(result, isTrue);
    });

    test('false when the only sibling is also selected in this batch', () {
      final result = bundleIdHasSurvivingSibling(
        bundleId: _xcode.bundleId,
        appPath: _xcode.path,
        allApps: [_xcode, _xcodeBeta],
        selectedPaths: {_xcode.path, _xcodeBeta.path},
      );

      expect(result, isFalse);
    });

    test('false when the bundle id is unknown', () {
      final unknownApp = InstalledApp(
        path: '/Applications/Mystery.app',
        bundleId: 'unknown',
        displayName: 'Mystery',
      );

      final result = bundleIdHasSurvivingSibling(
        bundleId: 'unknown',
        appPath: unknownApp.path,
        allApps: [unknownApp],
        selectedPaths: const {},
      );

      expect(result, isFalse);
    });

    test('matches case-insensitively (APFS default)', () {
      final upper = InstalledApp(
        path: _xcode.path,
        bundleId: 'COM.APPLE.DT.XCODE',
        displayName: 'Xcode',
      );

      final result = bundleIdHasSurvivingSibling(
        bundleId: upper.bundleId,
        appPath: upper.path,
        allApps: [upper, _xcodeBeta],
        selectedPaths: {upper.path},
      );

      expect(result, isTrue);
    });

    test('false when there is no other app at all', () {
      final result = bundleIdHasSurvivingSibling(
        bundleId: _xcode.bundleId,
        appPath: _xcode.path,
        allApps: [_xcode],
        selectedPaths: const {},
      );

      expect(result, isFalse);
    });
  });

  group('survivingSiblingNames', () {
    test('collects the sibling\'s own basename', () {
      final names = survivingSiblingNames(
        bundleId: _xcode.bundleId,
        appPath: _xcode.path,
        allApps: [_xcode, _xcodeBeta],
        selectedPaths: {_xcode.path},
      );

      expect(names, contains('xcode-beta'));
    });

    test('also collects the version-stripped base name when it differs', () {
      final nightlyApp = InstalledApp(
        path: '/Applications/Zed Nightly.app',
        bundleId: 'dev.zed.Zed-Nightly',
        displayName: 'Zed Nightly',
      );
      final stable = InstalledApp(
        path: '/Applications/Zed.app',
        bundleId: 'dev.zed.Zed-Nightly',
        displayName: 'Zed',
      );

      final names = survivingSiblingNames(
        bundleId: stable.bundleId,
        appPath: stable.path,
        allApps: [stable, nightlyApp],
        selectedPaths: {stable.path},
      );

      expect(names, containsAll(['zed nightly']));
    });
  });

  group('siblingGuardLevelFor', () {
    test('none when there is no surviving sibling', () {
      final level = siblingGuardLevelFor(
        bundleId: _xcode.bundleId,
        appPath: _xcode.path,
        displayName: _xcode.displayName,
        allApps: [_xcode],
        selectedPaths: const {},
      );

      expect(level, SiblingGuardLevel.none);
    });

    test('guard when a sibling survives but names do not collide', () {
      final level = siblingGuardLevelFor(
        bundleId: _xcode.bundleId,
        appPath: _xcode.path,
        displayName: _xcode.displayName,
        allApps: [_xcode, _xcodeBeta],
        selectedPaths: {_xcode.path},
      );

      expect(level, SiblingGuardLevel.guard);
    });

    test('guardLogin when the surviving sibling\'s name collides', () {
      final level = siblingGuardLevelFor(
        bundleId: _iterm2.bundleId,
        appPath: _iterm2.path,
        displayName: _iterm2.displayName,
        allApps: [_iterm2, _iterm2Beta],
        selectedPaths: {_iterm2.path},
      );

      expect(level, SiblingGuardLevel.guardLogin);
    });
  });
}
