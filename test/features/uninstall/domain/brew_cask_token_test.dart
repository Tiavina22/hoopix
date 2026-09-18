import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/uninstall/domain/entities/brew_cask_token.dart';

void main() {
  group('caskTokenFromCaskroomPath', () {
    test('reads the token under either Caskroom', () {
      expect(
        caskTokenFromCaskroomPath(
          '/opt/homebrew/Caskroom/visual-studio-code/1.2/Code.app',
        ),
        'visual-studio-code',
      );
      expect(
        caskTokenFromCaskroomPath('/usr/local/Caskroom/iterm2/3.5/iTerm.app'),
        'iterm2',
      );
    });

    test('rejects anything outside a Caskroom', () {
      expect(caskTokenFromCaskroomPath('/Applications/Code.app'), isNull);
      expect(
        caskTokenFromCaskroomPath('/opt/homebrew/Caskroomx/code/1/Code.app'),
        isNull,
      );
    });

    test('rejects a component that is not a plain cask token', () {
      expect(
        caskTokenFromCaskroomPath('/opt/homebrew/Caskroom/temurin@21/21/x'),
        isNull,
      );
      expect(
        caskTokenFromCaskroomPath('/opt/homebrew/Caskroom/Code.app'),
        isNull,
      );
      expect(caskTokenFromCaskroomPath('/opt/homebrew/Caskroom/'), isNull);
    });
  });

  test('caskListContains matches whole lines only', () {
    const list = 'firefox\nvisual-studio-code\n';
    expect(caskListContains(list, 'firefox'), isTrue);
    expect(caskListContains(list, 'visual-studio'), isFalse);
    expect(caskListContains(list, ''), isFalse);
  });

  test('caskListMatchingName compares the bundle name case-insensitively', () {
    const list = 'firefox\nzoom\n';
    expect(caskListMatchingName(list, 'Firefox.app'), 'firefox');
    expect(caskListMatchingName(list, 'Firefox Nightly.app'), isNull);
    expect(caskListMatchingName(list, '.app'), isNull);
  });

  group('brewInfoOwnsApp', () {
    test('accepts info that names the exact app path', () {
      expect(
        brewInfoOwnsApp(
          'Artifacts\n/Users/me/Applications/Code.app (App)',
          '/Users/me/Applications/Code.app',
        ),
        isTrue,
      );
    });

    test('accepts the bundle name only for an app in /Applications', () {
      const info = '==> Artifacts\nVisual Studio Code.app (App)';
      expect(
        brewInfoOwnsApp(info, '/Applications/Visual Studio Code.app'),
        isTrue,
      );
      expect(
        brewInfoOwnsApp(info, '/Users/me/Applications/Visual Studio Code.app'),
        isFalse,
      );
    });

    test('rejects info about some other app', () {
      expect(
        brewInfoOwnsApp('Firefox.app (App)', '/Applications/Code.app'),
        isFalse,
      );
    });
  });
}
