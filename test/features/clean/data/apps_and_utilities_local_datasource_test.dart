import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/data/datasources/apps_and_utilities_local_datasource.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_apps_utils_home_');
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

  List<String> targets() =>
      AppsAndUtilitiesLocalDataSource(home: home.path).enumerate().paths;

  test('section name matches the constant every other section uses', () {
    final result = AppsAndUtilitiesLocalDataSource(home: home.path).enumerate();
    expect(result.section, AppsAndUtilitiesLocalDataSource.appsAndUtilities);
  });

  group(
    'protected top-level Caches targets, reached through their children',
    () {
      test('communication and AI apps', () async {
        await makeDir('Library/Caches/us.zoom.xos/blob');
        await makeDir('Library/Caches/com.tencent.qq/blob');
        await makeDir('Library/Caches/com.openai.chat/blob');
        await makeDir('Library/Caches/com.anthropic.claudefordesktop/blob');

        final result = targets();

        expect(
          result,
          contains('${home.path}/Library/Caches/us.zoom.xos/blob'),
        );
        expect(
          result,
          contains('${home.path}/Library/Caches/com.tencent.qq/blob'),
        );
        expect(
          result,
          contains('${home.path}/Library/Caches/com.openai.chat/blob'),
        );
        expect(
          result,
          contains(
            '${home.path}/Library/Caches/com.anthropic.claudefordesktop/blob',
          ),
        );
      });

      test('single-app whole-directory targets', () async {
        await makeDir('Library/Caches/com.reincubate.camo');
        await makeDir('Library/Caches/com.readdle.smartemail-Mac');
        await makeDir('Library/Caches/com.todoist.mac.Todoist');
        await makeDir('Library/Caches/com.colliderli.iina');

        final result = targets();

        expect(
          result,
          contains('${home.path}/Library/Caches/com.reincubate.camo'),
        );
        expect(
          result,
          contains('${home.path}/Library/Caches/com.readdle.smartemail-Mac'),
        );
        expect(
          result,
          contains('${home.path}/Library/Caches/com.todoist.mac.Todoist'),
        );
        expect(
          result,
          contains('${home.path}/Library/Caches/com.colliderli.iina'),
        );
      });

      test(
        'prefix-matched whole directories and their grandchildren',
        () async {
          await makeDir('Library/Caches/com.cleanshot.helper');
          await makeDir('Library/Caches/com.adobe.PhotoshopBridge/blob');
          await makeDir('Library/Caches/com.teamviewer.TeamViewer/blob');

          final result = targets();

          expect(
            result,
            contains('${home.path}/Library/Caches/com.cleanshot.helper'),
          );
          expect(
            result,
            contains(
              '${home.path}/Library/Caches/com.adobe.PhotoshopBridge/blob',
            ),
          );
          expect(
            result,
            contains(
              '${home.path}/Library/Caches/com.teamviewer.TeamViewer/blob',
            ),
          );
        },
      );
    },
  );

  group(
    'never repeats a top-level Caches child userEssentials already sweeps whole',
    () {
      test('unprotected app caches across every group', () async {
        final unprotected = [
          'com.tencent.meeting',
          'com.feishu.dingding',
          'CCTClearcutLogger',
          'Adobe',
          'org.blenderfoundation.blender',
          'com.tw93.MiaoYan',
          'com.kugou.mac',
          'tv.danmaku.bili',
          'net.xmac.aria2gui',
          'com.valvesoftware.steam',
          'com.youdao.YoudaoDict',
          'com.mitchellh.ghostty',
          'com.runjuu.Input-Source-Pro',
          'com.logseq.notes',
          'cx.c3.theunarchiver',
          'com.sunlogin.client',
        ];
        for (final name in unprotected) {
          await makeDir('Library/Caches/$name/blob');
        }

        final result = targets();

        for (final name in unprotected) {
          expect(
            result,
            isNot(contains('${home.path}/Library/Caches/$name/blob')),
            reason: '$name should not be repeated here',
          );
        }
      });

      test(
        'the whole translation-apps group is redundant and contributes nothing',
        () async {
          await makeDir('Library/Caches/com.youdao.YoudaoDict/blob');
          await makeDir('Library/Caches/com.eudic.dict/blob');
          await makeDir('Library/Caches/com.bob-build.Bob/blob');

          final result = targets();

          expect(result.any((p) => p.contains('YoudaoDict')), isFalse);
          expect(result.any((p) => p.contains('com.eudic')), isFalse);
          expect(result.any((p) => p.contains('bob-build')), isFalse);
        },
      );
    },
  );

  test(
    'reaches container caches that need a deeper or differently-named path',
    () async {
      await makeDir(
        'Library/Containers/is.follow/Data/Library/Application Support/Folo/Cache/Cache_Data/blob',
      );
      await makeDir(
        'Library/Containers/com.wuziqi.SenPlayer/Data/tmp/videoCache/blob',
      );
      await makeDir(
        'Library/Containers/com.tencent.QQMusicMac/Data/Library/Application Support/QQMusicMac/iCache/blob',
      );

      final result = targets();

      expect(
        result,
        contains(
          '${home.path}/Library/Containers/is.follow/Data/Library/Application Support'
          '/Folo/Cache/Cache_Data/blob',
        ),
      );
      expect(
        result,
        contains(
          '${home.path}/Library/Containers/com.wuziqi.SenPlayer/Data/tmp/videoCache/blob',
        ),
      );
      expect(
        result,
        contains(
          '${home.path}/Library/Containers/com.tencent.QQMusicMac/Data/Library'
          '/Application Support/QQMusicMac/iCache/blob',
        ),
      );
    },
  );

  test(
    'never repeats a container cache the generic App caches sweep already reaches',
    () async {
      await makeDir(
        'Library/Containers/com.ranchero.NetNewsWire-Evergreen/Data/Library/Caches/blob',
      );
      await makeDir(
        'Library/Containers/com.ideasoncanvas.mindnode/Data/Library/Caches/blob',
      );
      await makeDir(
        'Library/Containers/com.tencent.QQMusicMac/Data/Library/Caches/blob',
      );

      final result = targets();

      expect(result.any((p) => p.contains('NetNewsWire')), isFalse);
      expect(result.any((p) => p.contains('mindnode')), isFalse);
      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Containers/com.tencent.QQMusicMac/Data/Library/Caches/blob',
          ),
        ),
      );
    },
  );

  group('Spotify', () {
    test('proposes the cache when there is no offline music', () async {
      await makeDir('Library/Caches/com.spotify.client/blob');

      expect(
        targets(),
        contains('${home.path}/Library/Caches/com.spotify.client/blob'),
      );
    });

    test('protects the cache when offline.bnk has real content', () async {
      await makeDir('Library/Caches/com.spotify.client/blob');
      await makeFile(
        'Library/Application Support/Spotify/PersistentCache/Storage/offline.bnk',
      );
      await File(
        '${home.path}/Library/Application Support/Spotify/PersistentCache/Storage/offline.bnk',
      ).writeAsBytes(List.filled(2048, 0));

      expect(
        targets(),
        isNot(contains('${home.path}/Library/Caches/com.spotify.client/blob')),
      );
    });

    test('an empty offline.bnk is not evidence of offline music', () async {
      await makeDir('Library/Caches/com.spotify.client/blob');
      await makeFile(
        'Library/Application Support/Spotify/PersistentCache/Storage/offline.bnk',
      );

      expect(
        targets(),
        contains('${home.path}/Library/Caches/com.spotify.client/blob'),
      );
    });

    test('protects the cache when an encrypted track blob is present', () async {
      await makeDir('Library/Caches/com.spotify.client/blob');
      await makeFile(
        'Library/Application Support/Spotify/PersistentCache/Storage/abc/track.file',
      );

      expect(
        targets(),
        isNot(contains('${home.path}/Library/Caches/com.spotify.client/blob')),
      );
    });
  });

  group('Apple Podcasts container temp files', () {
    test('reaches StreamedMedia, artwork and download-temp entries', () async {
      await makeDir(
        'Library/Containers/com.apple.podcasts/Data/tmp/StreamedMedia',
      );
      await makeFile('Library/Containers/com.apple.podcasts/Data/tmp/art.heic');
      await makeFile(
        'Library/Containers/com.apple.podcasts/Data/tmp/cover.img',
      );
      await makeFile(
        'Library/Containers/com.apple.podcasts/Data/tmp/abcCFNetworkDownload123.tmp',
      );
      await makeFile(
        'Library/Containers/com.apple.podcasts/Data/tmp/unrelated.txt',
      );

      final result = targets();

      expect(
        result,
        contains(
          '${home.path}/Library/Containers/com.apple.podcasts/Data/tmp/StreamedMedia',
        ),
      );
      expect(
        result,
        contains(
          '${home.path}/Library/Containers/com.apple.podcasts/Data/tmp/art.heic',
        ),
      );
      expect(
        result,
        contains(
          '${home.path}/Library/Containers/com.apple.podcasts/Data/tmp/cover.img',
        ),
      );
      expect(
        result,
        contains(
          '${home.path}/Library/Containers/com.apple.podcasts/Data/tmp/abcCFNetworkDownload123.tmp',
        ),
      );
      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Containers/com.apple.podcasts/Data/tmp/unrelated.txt',
          ),
        ),
      );
    });
  });

  group('Neat Download Manager stale segments', () {
    test(
      'proposes a numbered segment whose marker is older than 30 days',
      () async {
        await makeFile(
          'Library/Application Support/com.NeatDownloadManager/42/seg.x0',
          modified: DateTime.now().subtract(const Duration(days: 45)),
        );

        expect(
          targets(),
          contains(
            '${home.path}/Library/Application Support/com.NeatDownloadManager/42',
          ),
        );
      },
    );

    test('leaves a recent segment and history database alone', () async {
      await makeFile(
        'Library/Application Support/com.NeatDownloadManager/7/seg.x0',
        modified: DateTime.now().subtract(const Duration(days: 2)),
      );
      await makeFile(
        'Library/Application Support/com.NeatDownloadManager/NeatDB.db',
      );

      final result = targets();

      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Application Support/com.NeatDownloadManager/7',
          ),
        ),
      );
      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Application Support/com.NeatDownloadManager/NeatDB.db',
          ),
        ),
      );
    });

    test('ignores a non-numbered directory even with an old seg.x0', () async {
      await makeFile(
        'Library/Application Support/com.NeatDownloadManager/not-a-segment/seg.x0',
        modified: DateTime.now().subtract(const Duration(days: 90)),
      );

      expect(
        targets(),
        isNot(
          contains(
            '${home.path}/Library/Application Support/com.NeatDownloadManager/not-a-segment',
          ),
        ),
      );
    });
  });

  test(
    'sweeps home dotfiles and shell-utility logs directly, never through Caches',
    () async {
      await makeFile('.zcompdump-host-5.9');
      await makeFile('.lesshst');
      await makeFile('.viminfo.tmp');
      await makeDir('.cacher/logs/blob');
      await makeDir('.kite/logs/blob');

      final result = targets();

      expect(result, contains('${home.path}/.zcompdump-host-5.9'));
      expect(result, contains('${home.path}/.lesshst'));
      expect(result, contains('${home.path}/.viminfo.tmp'));
      expect(result, contains('${home.path}/.cacher/logs/blob'));
      expect(result, contains('${home.path}/.kite/logs/blob'));
    },
  );

  test(
    'sweeps gaming-platform Application Support subpaths that Caches never covers',
    () async {
      await makeDir('Library/Application Support/Steam/htmlcache/blob');
      await makeDir(
        'Library/Application Support/Steam/steamapps/shadercache/blob',
      );
      await makeDir('Library/Application Support/Battle.net/Cache/blob');
      await makeDir('.lunarclient/game-cache/blob');
      await makeDir('.lunarclient/offline/profile-a/logs/blob');
      await makeDir('.lunarclient/offline/files/id-1/logs/blob');

      final result = targets();

      expect(
        result,
        contains(
          '${home.path}/Library/Application Support/Steam/htmlcache/blob',
        ),
      );
      expect(
        result,
        contains(
          '${home.path}/Library/Application Support/Steam/steamapps/shadercache/blob',
        ),
      );
      expect(
        result,
        contains(
          '${home.path}/Library/Application Support/Battle.net/Cache/blob',
        ),
      );
      expect(result, contains('${home.path}/.lunarclient/game-cache/blob'));
      expect(
        result,
        contains('${home.path}/.lunarclient/offline/profile-a/logs/blob'),
      );
      expect(
        result,
        contains('${home.path}/.lunarclient/offline/files/id-1/logs/blob'),
      );
    },
  );

  test('a missing home tree does not throw', () {
    expect(targets, returnsNormally);
  });
}
