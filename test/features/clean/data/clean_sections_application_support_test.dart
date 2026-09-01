import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_app_support_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  List<String> targets() => CleanSectionsLocalDataSource(home: home.path)
      .enumerate()
      .singleWhere(
        (section) =>
            section.section == CleanSectionsLocalDataSource.applicationSupport,
      )
      .paths;

  test('reaches an ordinary app\'s known cache-shaped subdirectories', () async {
    await makeDir('Library/Application Support/SomeApp/Code Cache/blob');
    await makeDir('Library/Application Support/SomeApp/GPUCache/blob');
    await makeDir(
      'Library/Application Support/SomeApp/Crashpad/completed/blob',
    );

    final result = targets();

    expect(
      result,
      contains(
        '${home.path}/Library/Application Support/SomeApp/Code Cache/blob',
      ),
    );
    expect(
      result,
      contains(
        '${home.path}/Library/Application Support/SomeApp/GPUCache/blob',
      ),
    );
    expect(
      result,
      contains(
        '${home.path}/Library/Application Support/SomeApp/Crashpad/completed/blob',
      ),
    );
  });

  test(
    'only reaches Cache/CachedData when a marker proves it Electron-shaped',
    () async {
      await makeDir('Library/Application Support/PlainApp/Cache/blob');
      await makeDir('Library/Application Support/PlainApp/CachedData/blob');
      await makeDir('Library/Application Support/ElectronApp/GPUCache/marker');
      await makeDir('Library/Application Support/ElectronApp/Cache/blob');
      await makeDir('Library/Application Support/ElectronApp/CachedData/blob');

      final result = targets();

      // No marker directory: an arbitrary app's "Cache" folder is ambiguous.
      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Application Support/PlainApp/Cache/blob',
          ),
        ),
      );
      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Application Support/PlainApp/CachedData/blob',
          ),
        ),
      );
      // A marker present: this really is a Chromium/Electron-shaped cache.
      expect(
        result,
        contains(
          '${home.path}/Library/Application Support/ElectronApp/Cache/blob',
        ),
      );
      expect(
        result,
        contains(
          '${home.path}/Library/Application Support/ElectronApp/CachedData/blob',
        ),
      );
    },
  );

  test(
    'never looks inside a com.apple.* or otherwise vendor-protected app',
    () async {
      await makeDir(
        'Library/Application Support/com.apple.something/Code Cache/blob',
      );
      // "Claude" is one of shouldProtectData's plain display-name keyword
      // rules, not just a com.* bundle id pattern.
      await makeDir('Library/Application Support/Claude/Code Cache/blob');

      final result = targets();

      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Application Support/com.apple.something/Code Cache/blob',
          ),
        ),
      );
      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Application Support/Claude/Code Cache/blob',
          ),
        ),
      );
    },
  );

  test('reaches the allowlisted group container logs', () async {
    await makeDir(
      'Library/Group Containers/group.com.apple.contentdelivery/Logs/blob',
    );

    expect(
      targets(),
      contains(
        '${home.path}/Library/Group Containers/group.com.apple.contentdelivery/Logs/blob',
      ),
    );
  });

  test('a missing home tree does not throw', () {
    expect(targets, returnsNormally);
  });
}
