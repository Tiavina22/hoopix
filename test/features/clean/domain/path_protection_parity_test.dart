import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/domain/entities/path_protection.dart';

/// Differential test against Mole itself.
///
/// The expectations below are not hand-written judgements — they were
/// produced by running Mole's real `should_protect_path` from
/// `lib/core/app_protection.sh` over these exact paths with HOME set to
/// /Users/tester, and recording what it answered. If hoopix's port ever
/// disagrees with the shell it was ported from, one of these fails.
///
/// Regenerating: source Mole's `app_protection_data.sh` and
/// `app_protection.sh`, then call `should_protect_path` per path.
///
/// A wider sweep of 1971 synthesized paths (every entry of both bundle
/// lists, plus common real cleanup targets) found exactly two disagreements,
/// both deliberate: Mole protects its own `~/Library/Logs/mole`, hoopix
/// protects its own `~/Library/Logs/hoopix`. That rule is "never delete the
/// log you are writing to", so the app name is supposed to differ. The two
/// cases are pinned below so the substitution stays intentional.
const _home = '/Users/tester';

/// (path, whether Mole protects it)
const _moleVerdicts = <(String, bool)>[
  ('/Users/tester/Library/Caches/com.apple.systempreferences.cache', true),
  ('/Users/tester/Library/Caches/com.apple.finder.cache', true),
  ('/Users/tester/Library/Preferences/com.apple.dock.plist', true),
  ('/Users/tester/Library/Keychains/login.keychain-db', true),
  ('/Users/tester/Library/Mail/V10', true),
  ('/Users/tester/Library/Mobile Documents/com~apple~CloudDocs', true),
  ('/Library/Audio/Plug-Ins/VST3/FabFilter Pro-Q 3.vst3', true),
  ('/Users/tester/Library/Caches/com.apple.coreaudio', true),
  ('/Users/tester/Library/Application Support/com.apple.wallpaper', true),
  ('/Users/tester/Library/Caches/Adobe Photoshop', true),
  ('/Users/tester/.cache', true),
  ('/Users/tester/.config', true),
  ('/Users/tester/.local/share', true),
  ('/Users/tester/.config/zed', false),
  ('/Users/tester/.local/share/firefox', false),
  ('/Users/tester/Library/Containers/com.1password.1password/Data', true),
  ('/Users/tester/Library/Containers/com.example.notes/Data/Library/Caches/x', false),
  ('/Users/tester/Library/Containers/com.apple.Settings/Data/Library/Caches/x', true),
  ('/private/var/folders/ab/C/com.crowdstrike.falcon', true),
  ('/Users/tester/Library/Caches/com.crowdstrike.falcon', true),
  ('/Users/tester/.orbstack/data', true),
  ('/Users/tester/Library/Caches/com.example.app', false),
  ('/Users/tester/Library/Caches/some-random-tool', false),
  ('/Users/tester/Library/Caches/Google/Chrome', false),
  ('/Users/tester/Library/Caches/com.spotify.client', true),
  ('/Users/tester/Library/Logs/DiagnosticReports', false),
  ('/Users/tester/Library/Caches/pip', false),
  ('/Users/tester/Library/Caches/Homebrew', false),
  ('/Users/tester/Library/Developer/Xcode/DerivedData', false),
  ('/Users/tester/Library/Caches/JetBrains', true),
  ('/Users/tester/Library/Caches/com.microsoft.VSCode', true),
  ('/Users/tester/Library/Application Support/Codex/state', true),
  ('/Users/tester/.codex/sessions', true),
];

void main() {
  test('every verdict matches the shell implementation it was ported from', () {
    final disagreements = <String>[];

    for (final (path, moleProtects) in _moleVerdicts) {
      final hoopixProtects = shouldProtectPath(path, home: _home);
      if (hoopixProtects != moleProtects) {
        disagreements.add(
          '$path: Mole says ${moleProtects ? "protect" : "allow"}, '
          'hoopix says ${hoopixProtects ? "protect" : "allow"}',
        );
      }
    }

    expect(disagreements, isEmpty, reason: disagreements.join('\n'));
  });

  test('each app protects its own runtime log, not the other one', () {
    // The one rule where the two implementations are meant to disagree.
    expect(shouldProtectPath('$_home/Library/Logs/hoopix/run.log', home: _home), isTrue);
    expect(shouldProtectPath('$_home/Library/Logs/mole/run.log', home: _home), isFalse);
  });

  test('the fixture actually covers both verdicts', () {
    // A fixture that drifted to all-protect or all-allow would pass the
    // comparison above while testing nothing.
    expect(_moleVerdicts.where((v) => v.$2), isNotEmpty);
    expect(_moleVerdicts.where((v) => !v.$2), isNotEmpty);
  });
}
