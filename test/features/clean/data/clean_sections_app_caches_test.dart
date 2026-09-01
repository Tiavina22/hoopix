import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_app_caches_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  Future<File> makeFile(String relative, {DateTime? modified}) async {
    final file = File('${home.path}/$relative');
    await file.create(recursive: true);
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  List<String> appCacheTargets() =>
      CleanSectionsLocalDataSource(home: home.path)
          .enumerate()
          .singleWhere(
            (section) =>
                section.section == CleanSectionsLocalDataSource.appCaches,
          )
          .paths;

  test(
    'reaches the curated Apple system caches that userEssentials must keep, not clean',
    () async {
      await makeDir('Library/Caches/com.apple.photoanalysisd');
      await makeDir('Library/Caches/com.apple.akd');
      await makeDir('Library/Caches/com.apple.QuickLook.thumbnailcache');
      await makeDir('Library/Caches/com.apple.iconservices');
      await makeDir('Library/Caches/com.apple.iconservices.store');
      await makeDir('Library/Caches/com.apple.WebKit.Networking/blob');
      await makeDir('Library/Caches/com.apple.helpd/blob');
      await makeDir('Library/Caches/com.apple.AppleMediaServices/blob');
      await makeDir('Library/Caches/com.apple.duetexpertd/blob');
      await makeDir('Library/Caches/com.apple.parsecd/blob');
      await makeDir('Library/Caches/com.apple.python/blob');

      final targets = appCacheTargets();

      // Whole-directory targets: each is proposed itself, not reached
      // through a child, since userEssentials could never propose them —
      // they are blanket-protected as top-level Caches children.
      expect(
        targets,
        contains('${home.path}/Library/Caches/com.apple.photoanalysisd'),
      );
      expect(targets, contains('${home.path}/Library/Caches/com.apple.akd'));
      expect(
        targets,
        contains(
          '${home.path}/Library/Caches/com.apple.QuickLook.thumbnailcache',
        ),
      );
      expect(
        targets,
        contains('${home.path}/Library/Caches/com.apple.iconservices'),
      );
      expect(
        targets,
        contains('${home.path}/Library/Caches/com.apple.iconservices.store'),
      );
      expect(
        targets,
        contains(
          '${home.path}/Library/Caches/com.apple.WebKit.Networking/blob',
        ),
      );
      expect(
        targets,
        contains('${home.path}/Library/Caches/com.apple.helpd/blob'),
      );
      expect(
        targets,
        contains(
          '${home.path}/Library/Caches/com.apple.AppleMediaServices/blob',
        ),
      );
      expect(
        targets,
        contains('${home.path}/Library/Caches/com.apple.duetexpertd/blob'),
      );
      expect(
        targets,
        contains('${home.path}/Library/Caches/com.apple.parsecd/blob'),
      );
      expect(
        targets,
        contains('${home.path}/Library/Caches/com.apple.python/blob'),
      );
    },
  );

  test(
    'does not repeat a top-level Caches child that userEssentials already sweeps whole',
    () async {
      // GeoServices is not blanket-protected, so proposing it here too
      // would double-count its size across two sections.
      await makeDir('Library/Caches/GeoServices/blob');

      expect(
        appCacheTargets(),
        isNot(contains('${home.path}/Library/Caches/GeoServices/blob')),
      );
    },
  );

  test(
    'sweeps saved application state, diagnostic reports, identity caches and suggestions',
    () async {
      await makeDir('Library/Saved Application State/com.example.savedState');
      await makeDir('Library/DiagnosticReports/Example-2026-01-01.crash');
      await makeDir('Library/IdentityCaches/identity.db');
      await makeDir('Library/Suggestions/blob');

      final targets = appCacheTargets();

      expect(
        targets,
        contains(
          '${home.path}/Library/Saved Application State/com.example.savedState',
        ),
      );
      expect(
        targets,
        contains(
          '${home.path}/Library/DiagnosticReports/Example-2026-01-01.crash',
        ),
      );
      expect(
        targets,
        contains('${home.path}/Library/IdentityCaches/identity.db'),
      );
      expect(targets, contains('${home.path}/Library/Suggestions/blob'));
    },
  );

  test(
    'proposes Calendar Cache and every AddressBook source photo cache',
    () async {
      await makeDir('Library/Application Support/AddressBook/Sources/ABC-123');
      await makeDir('Library/Application Support/AddressBook/Sources/DEF-456');

      final targets = appCacheTargets();

      expect(
        targets,
        contains('${home.path}/Library/Calendars/Calendar Cache'),
      );
      expect(
        targets,
        contains(
          '${home.path}/Library/Application Support/AddressBook/Sources/ABC-123/Photos.cache',
        ),
      );
      expect(
        targets,
        contains(
          '${home.path}/Library/Application Support/AddressBook/Sources/DEF-456/Photos.cache',
        ),
      );
    },
  );

  test(
    'proposes CrashReporter files older than 30 days, not recent ones',
    () async {
      await makeFile(
        'Library/Application Support/CrashReporter/old.crash',
        modified: DateTime.now().subtract(const Duration(days: 45)),
      );
      await makeFile(
        'Library/Application Support/CrashReporter/recent.crash',
        modified: DateTime.now().subtract(const Duration(days: 2)),
      );

      final targets = appCacheTargets();

      expect(
        targets,
        contains(
          '${home.path}/Library/Application Support/CrashReporter/old.crash',
        ),
      );
      expect(
        targets,
        isNot(
          contains(
            '${home.path}/Library/Application Support/CrashReporter/recent.crash',
          ),
        ),
      );
    },
  );

  test(
    'sweeps Messages preview and sticker caches, never attachments themselves',
    () async {
      await makeDir('Library/Messages/StickerCache/sticker.db');
      await makeDir('Library/Messages/Caches/Previews/Attachments/preview.jpg');
      await makeDir('Library/Messages/Attachments/real-attachment.pdf');

      final targets = appCacheTargets();

      expect(
        targets,
        contains('${home.path}/Library/Messages/StickerCache/sticker.db'),
      );
      expect(
        targets,
        contains(
          '${home.path}/Library/Messages/Caches/Previews/Attachments/preview.jpg',
        ),
      );
      expect(
        targets,
        isNot(
          contains(
            '${home.path}/Library/Messages/Attachments/real-attachment.pdf',
          ),
        ),
      );
    },
  );

  test('sweeps the curated Apple sandboxed cache allowlist', () async {
    await makeDir(
      'Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/tile.bin',
    );
    await makeDir(
      'Library/Containers/com.apple.stocks/Data/Library/Caches/quote.json',
    );

    final targets = appCacheTargets();

    expect(
      targets,
      contains(
        '${home.path}/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/tile.bin',
      ),
    );
    expect(
      targets,
      contains(
        '${home.path}/Library/Containers/com.apple.stocks/Data/Library/Caches/quote.json',
      ),
    );
  });

  group('generic container cache sweep', () {
    test('proposes an ordinary third-party container cache', () async {
      await makeDir(
        'Library/Containers/com.example.app/Data/Library/Caches/blob',
      );

      expect(
        appCacheTargets(),
        contains(
          '${home.path}/Library/Containers/com.example.app/Data/Library/Caches/blob',
        ),
      );
    });

    test(
      'never looks inside a com.apple.* container the allowlist did not name',
      () async {
        await makeDir(
          'Library/Containers/com.apple.unnamed.example/Data/Library/Caches/blob',
        );

        expect(
          appCacheTargets(),
          isNot(
            contains(
              '${home.path}/Library/Containers/com.apple.unnamed.example/Data/Library/Caches/blob',
            ),
          ),
        );
      },
    );

    test(
      'skips a container whose bundle id names a system-critical component',
      () async {
        // Third-party, so it clears shouldProtectData — only isCriticalSystemComponent stops it.
        await makeDir(
          'Library/Containers/com.example.SystemSettingsHelper/Data/Library/Caches/blob',
        );

        expect(
          appCacheTargets(),
          isNot(
            contains(
              '${home.path}/Library/Containers/com.example.SystemSettingsHelper/Data/Library/Caches/blob',
            ),
          ),
        );
      },
    );

    test('never descends into a symlinked container', () async {
      await makeDir(
        'Library/Containers/real-container/Data/Library/Caches/blob',
      );
      await makeDir('Library/Containers');
      await Link(
        '${home.path}/Library/Containers/aliased',
      ).create('${home.path}/Library/Containers/real-container');

      // The symlink itself is not proposed, and its target is only reachable
      // through the real name, not the alias.
      expect(
        appCacheTargets(),
        isNot(
          contains(
            '${home.path}/Library/Containers/aliased/Data/Library/Caches/blob',
          ),
        ),
      );
    });
  });

  group('group container cache sweep', () {
    test(
      'proposes caches and logs for an ordinary third-party group container',
      () async {
        await makeDir(
          'Library/Group Containers/com.example.shared/Caches/blob',
        );
        await makeDir(
          'Library/Group Containers/com.example.shared/Logs/run.log',
        );

        final targets = appCacheTargets();

        expect(
          targets,
          contains(
            '${home.path}/Library/Group Containers/com.example.shared/Caches/blob',
          ),
        );
        expect(
          targets,
          contains(
            '${home.path}/Library/Group Containers/com.example.shared/Logs/run.log',
          ),
        );
      },
    );

    test('never sweeps an Apple-owned group container', () async {
      await makeDir(
        'Library/Group Containers/group.com.apple.example/Caches/blob',
      );

      expect(
        appCacheTargets(),
        isNot(
          contains(
            '${home.path}/Library/Group Containers/group.com.apple.example/Caches/blob',
          ),
        ),
      );
    });

    test(
      'skips a group container that shares an id with a Safari Web Extension container',
      () async {
        await makeDir('Library/Group Containers/com.example.ext/Caches/blob');
        await makeDir(
          'Library/Containers/com.example.ext/SafariWebExtensionHandler',
        );

        expect(
          appCacheTargets(),
          isNot(
            contains(
              '${home.path}/Library/Group Containers/com.example.ext/Caches/blob',
            ),
          ),
        );
      },
    );

    test(
      'a protected owner still contributes its logs but not its caches',
      () async {
        await makeDir(
          'Library/Group Containers/group.com.1password.example/Caches/blob',
        );
        await makeDir(
          'Library/Group Containers/group.com.1password.example/Logs/run.log',
        );

        final targets = appCacheTargets();

        expect(
          targets,
          isNot(
            contains(
              '${home.path}/Library/Group Containers/group.com.1password.example/Caches/blob',
            ),
          ),
        );
        expect(
          targets,
          contains(
            '${home.path}/Library/Group Containers/group.com.1password.example/Logs/run.log',
          ),
        );
      },
    );
  });

  test(
    'proposes handoff pasteboard entries older than an hour, not fresh ones',
    () async {
      const pasteboard =
          'Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard';
      await makeFile(
        '$pasteboard/old-entry',
        modified: DateTime.now().subtract(const Duration(hours: 2)),
      );
      await makeFile('$pasteboard/fresh-entry', modified: DateTime.now());

      final targets = appCacheTargets();

      expect(targets, contains('${home.path}/$pasteboard/old-entry'));
      expect(targets, isNot(contains('${home.path}/$pasteboard/fresh-entry')));
    },
  );

  test('a missing home tree does not throw', () {
    // Library/Calendars/Calendar Cache is proposed unconditionally, like the
    // other single-file targets — the funnel is what checks existence.
    expect(appCacheTargets, returnsNormally);
  });
}
