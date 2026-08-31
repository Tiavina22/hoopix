import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/domain/entities/path_protection.dart';

const _home = '/Users/tester';

bool protects(String path) => shouldProtectPath(path, home: _home);

void main() {
  group('system UI', () {
    test('protects the caches behind System Settings and Control Center', () {
      // Removing these is the blank-settings-panel bug.
      expect(protects('$_home/Library/Caches/com.apple.systempreferences.cache'), isTrue);
      expect(protects('$_home/Library/Caches/com.apple.Settings.cache'), isTrue);
      expect(protects('$_home/Library/Caches/com.apple.controlcenter.cache'), isTrue);
      expect(protects('$_home/Library/Containers/com.apple.SystemSettings'), isTrue);
    });

    test('protects Finder and Dock', () {
      expect(protects('$_home/Library/Caches/com.apple.finder.cache'), isTrue);
      expect(protects('$_home/Library/Preferences/com.apple.dock.plist'), isTrue);
    });

    test('matches the system keywords whatever their casing', () {
      expect(protects('/x/SystemSettings/y'), isTrue);
      expect(protects('/x/systemsettings/y'), isTrue);
      expect(protects('/x/ControlCenter/y'), isTrue);
      expect(protects('/x/controlcenter/y'), isTrue);
    });
  });

  group('user data wearing a cache-shaped name', () {
    test('protects keychains, mail, contacts and accounts', () {
      expect(protects('$_home/Library/Keychains/login.keychain-db'), isTrue);
      expect(protects('$_home/Library/Mail/V10'), isTrue);
      expect(protects('$_home/Library/Contacts/AddressBook.data'), isTrue);
      expect(protects('$_home/Library/Accounts/Accounts4.sqlite'), isTrue);
    });

    test('protects iCloud Drive', () {
      expect(protects('$_home/Library/Mobile Documents/com~apple~CloudDocs'), isTrue);
    });

    test('protects audio plug-ins and their licence state', () {
      expect(protects('/Library/Audio/Plug-Ins/VST3/FabFilter Pro-Q 3.vst3'), isTrue);
      expect(protects('$_home/Library/Preferences/com.paceap.eden.plist'), isTrue);
      expect(protects('/private/var/folders/ab/C/com.native-instruments.x'), isTrue);
    });

    test('protects CoreAudio, which has cost people their audio output', () {
      expect(protects('$_home/Library/Caches/com.apple.coreaudio'), isTrue);
      expect(protects('/x/coreaudiod/y'), isTrue);
    });

    test('protects wallpaper and aerial assets, which are user-selected', () {
      expect(
        protects('$_home/Library/Application Support/com.apple.idleassetsd/Customer'),
        isTrue,
      );
      expect(protects('$_home/Library/Application Support/com.apple.wallpaper'), isTrue);
    });

    test('protects Adobe caches, which hold licence state', () {
      expect(protects('$_home/Library/Caches/Adobe Photoshop'), isTrue);
      // The pattern needs the trailing space: bare "Adobe" is a different entry.
      expect(protects('$_home/Library/Caches/Adobe InDesign'), isTrue);
    });
  });

  group('shared home roots', () {
    test('protects the roots themselves', () {
      expect(protects('$_home/.cache'), isTrue);
      expect(protects('$_home/.config'), isTrue);
      expect(protects('$_home/.local'), isTrue);
      expect(protects('$_home/.local/share'), isTrue);
      // Casing varies on a case-insensitive volume and still resolves here.
      expect(protects('$_home/.Config'), isTrue);
    });

    test('leaves an app-specific child alone', () {
      expect(protects('$_home/.config/zed'), isFalse);
      expect(protects('$_home/.local/share/firefox'), isFalse);
    });
  });

  group('containers', () {
    test('protects a container belonging to a protected bundle', () {
      expect(protects('$_home/Library/Containers/com.1password.1password/Data'), isTrue);
    });

    test('lets a container cache through, since it is regenerable', () {
      // The bundle id was already judged; a Caches subdirectory inside the
      // container is rebuildable by definition.
      expect(
        protects('$_home/Library/Containers/com.example.notes/Data/Library/Caches/x'),
        isFalse,
      );
    });

    test('still protects a critical container cache by name', () {
      expect(
        protects('$_home/Library/Containers/com.apple.Settings/Data/Library/Caches/x'),
        isTrue,
      );
    });
  });

  group('endpoint security', () {
    test('protects EDR agent state under the Darwin folder', () {
      expect(
        isEndpointSecurityCachePath('/private/var/folders/ab/C/com.crowdstrike.falcon'),
        isTrue,
      );
      expect(protects('/private/var/folders/ab/C/com.crowdstrike.falcon'), isTrue);
      expect(isEndpointSecurityCachePath('/var/folders/ab/T/com.sentinelone.x'), isTrue);
    });

    test('the same vendor name outside var/folders is not this rule', () {
      expect(
        isEndpointSecurityCachePath('$_home/Library/Caches/com.crowdstrike.falcon'),
        isFalse,
      );
    });
  });

  group('OrbStack', () {
    test('protects live container images', () {
      expect(isOrbstackRuntimePath('$_home/.orbstack/data'), isTrue);
      expect(
        isOrbstackRuntimePath('$_home/Library/Group Containers/HUAQ24HBR6.dev.orbstack'),
        isTrue,
      );
      expect(protects('$_home/.orbstack/data'), isTrue);
    });
  });

  group('compiled model caches', () {
    test('protects the E5RT bundle cache and its immediate parent', () {
      expect(
        holdsCompiledModelCache('/x/com.apple.e5rt.e5bundlecache', directoryExists: (_) => false),
        isTrue,
      );
      // The parent counts too: the cache sits one level below it.
      expect(
        holdsCompiledModelCache('/x/SomeApp', directoryExists: (p) => p.endsWith('e5bundlecache')),
        isTrue,
      );
      expect(holdsCompiledModelCache('/x/SomeApp', directoryExists: (_) => false), isFalse);
    });
  });

  group('what stays cleanable', () {
    test('an ordinary app cache is not protected', () {
      expect(protects('$_home/Library/Caches/com.example.app'), isFalse);
      expect(protects('$_home/Library/Caches/some-random-tool'), isFalse);
    });

    test('an empty path is not protected, and not an error', () {
      expect(protects(''), isFalse);
    });
  });

  group('shouldProtectData', () {
    test('protects every Apple bundle', () {
      expect(shouldProtectData('com.apple.anything'), isTrue);
    });

    test('protects password managers and input methods', () {
      expect(shouldProtectData('com.1password.1password'), isTrue);
      expect(shouldProtectData('com.sogou.inputmethod'), isTrue);
      expect(shouldProtectData('SomeIME'), isTrue);
    });

    test('protects proxy tools under their many spellings', () {
      expect(shouldProtectData('ClashX'), isTrue);
      expect(shouldProtectData('clash-verge'), isTrue);
      expect(shouldProtectData('com.nssurge.surge-mac'), isTrue);
    });

    test('leaves an unrelated bundle alone', () {
      expect(shouldProtectData('com.example.randomapp'), isFalse);
    });
  });
}
