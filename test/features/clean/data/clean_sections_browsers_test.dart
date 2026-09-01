import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_browsers_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  List<String> browserTargets() => CleanSectionsLocalDataSource(home: home.path)
      .enumerate()
      .singleWhere(
        (section) => section.section == CleanSectionsLocalDataSource.browsers,
      )
      .paths;

  test('sweeps each child of the puppeteer browser cache', () async {
    await makeDir('.cache/puppeteer/chrome');

    expect(browserTargets(), contains('${home.path}/.cache/puppeteer/chrome'));
  });

  group('service worker cache sweep', () {
    test(
      'proposes an ordinary origin cache two levels below CacheStorage',
      () async {
        await makeDir(
          'Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage/abc/def',
        );

        expect(
          browserTargets(),
          contains(
            '${home.path}/Library/Application Support/Google/Chrome/Default'
            '/Service Worker/CacheStorage/abc/def',
          ),
        );
      },
    );

    test('leaves a protected collaboration-tool origin alone', () async {
      await makeDir(
        'Library/Application Support/Google/Chrome/Default/Service Worker'
        '/CacheStorage/abc/https_notion.so_0',
      );

      expect(
        browserTargets(),
        isNot(
          contains(
            '${home.path}/Library/Application Support/Google/Chrome/Default'
            '/Service Worker/CacheStorage/abc/https_notion.so_0',
          ),
        ),
      );
    });

    test('does not descend further than two levels', () async {
      await makeDir(
        'Library/Application Support/Google/Chrome/Default/Service Worker'
        '/CacheStorage/abc/def/too-deep',
      );

      final targets = browserTargets();

      expect(
        targets,
        contains(
          '${home.path}/Library/Application Support/Google/Chrome/Default'
          '/Service Worker/CacheStorage/abc/def',
        ),
      );
      expect(
        targets,
        isNot(
          contains(
            '${home.path}/Library/Application Support/Google/Chrome/Default'
            '/Service Worker/CacheStorage/abc/def/too-deep',
          ),
        ),
      );
    });

    test('sweeps every browser profile root, not only Chrome', () async {
      await makeDir(
        'Library/Application Support/Arc/Default/Service Worker/CacheStorage/abc/def',
      );
      await makeDir(
        'Library/Application Support/Arc/User Data/Default/Service Worker'
        '/CacheStorage/abc/def',
      );
      await makeDir(
        'Library/Application Support/Dia/User Data/Default/Service Worker'
        '/CacheStorage/abc/def',
      );
      await makeDir(
        'Library/Application Support/BraveSoftware/Brave-Browser/Default'
        '/Service Worker/CacheStorage/abc/def',
      );
      await makeDir(
        'Library/Application Support/Vivaldi/Default/Service Worker/CacheStorage/abc/def',
      );

      final targets = browserTargets();

      expect(
        targets,
        contains(
          '${home.path}/Library/Application Support/Arc/Default'
          '/Service Worker/CacheStorage/abc/def',
        ),
      );
      expect(
        targets,
        contains(
          '${home.path}/Library/Application Support/Arc/User Data/Default'
          '/Service Worker/CacheStorage/abc/def',
        ),
      );
      expect(
        targets,
        contains(
          '${home.path}/Library/Application Support/Dia/User Data/Default'
          '/Service Worker/CacheStorage/abc/def',
        ),
      );
      expect(
        targets,
        contains(
          '${home.path}/Library/Application Support/BraveSoftware/Brave-Browser/Default'
          '/Service Worker/CacheStorage/abc/def',
        ),
      );
      expect(
        targets,
        contains(
          '${home.path}/Library/Application Support/Vivaldi/Default'
          '/Service Worker/CacheStorage/abc/def',
        ),
      );
    });
  });

  test(
    'never proposes the top-level browser cache directories already swept elsewhere',
    () async {
      await makeDir('Library/Caches/Google/Chrome/blob');
      await makeDir('Library/Caches/com.apple.Safari/blob');

      final targets = browserTargets();

      expect(
        targets,
        isNot(contains('${home.path}/Library/Caches/Google/Chrome/blob')),
      );
      expect(
        targets,
        isNot(contains('${home.path}/Library/Caches/com.apple.Safari/blob')),
      );
    },
  );

  test('a missing home tree does not throw', () {
    expect(browserTargets, returnsNormally);
    expect(browserTargets(), isEmpty);
  });
}
