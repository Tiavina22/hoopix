import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/browser_profile_caches_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _running() => ProcessResult.success('123');
ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _unknown() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 2, 'usage'));

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp(
      'hoopix_browser_profiles_home_',
    );
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  Future<List<String>> targets(Map<String, ProcessResult> responses) async {
    final source = BrowserProfileCachesLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner(responses)),
    );
    return (await source.enumerate()).paths;
  }

  test('section name matches the constant Browsers uses', () async {
    final source = BrowserProfileCachesLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner(const {})),
    );
    final result = await source.enumerate();
    expect(result.section, CleanSectionsLocalDataSource.browsers);
  });

  group('Chrome', () {
    Future<void> makeChromeTree() async {
      await makeDir(
        'Library/Application Support/Google/Chrome/Default/Code Cache/blob',
      );
      await makeDir(
        'Library/Application Support/Google/Chrome/component_crx_cache/blob',
      );
    }

    test('reaches profile and top-level caches while Chrome is closed', () async {
      await makeChromeTree();

      final result = await targets({
        'pgrep -x Google Chrome': _notRunning(),
        'pgrep -x Google Chrome Helper': _notRunning(),
        'pgrep -f /Google Chrome.app/': _notRunning(),
      });

      expect(
        result,
        contains(
          '${home.path}/Library/Application Support/Google/Chrome/Default/Code Cache/blob',
        ),
      );
      expect(
        result,
        contains(
          '${home.path}/Library/Application Support/Google/Chrome/component_crx_cache/blob',
        ),
      );
    });

    test('proposes nothing while any Chrome process is running', () async {
      await makeChromeTree();

      final result = await targets({
        'pgrep -x Google Chrome': _running(),
        'pgrep -x Google Chrome Helper': _notRunning(),
        'pgrep -f /Google Chrome.app/': _notRunning(),
      });

      expect(result.any((p) => p.contains('Google/Chrome')), isFalse);
    });

    test(
      'proposes nothing when the process state cannot be confirmed',
      () async {
        await makeChromeTree();

        final result = await targets({
          'pgrep -x Google Chrome': _unknown(),
          'pgrep -x Google Chrome Helper': _notRunning(),
          'pgrep -f /Google Chrome.app/': _notRunning(),
        });

        expect(result.any((p) => p.contains('Google/Chrome')), isFalse);
      },
    );

    test(
      'proposes nothing, and never probes, when Chrome is not installed',
      () async {
        final result = await targets(const {});

        expect(result.any((p) => p.contains('Google/Chrome')), isFalse);
      },
    );
  });

  test('reaches both Arc roots (Arc/ and Arc/User Data/)', () async {
    await makeDir('Library/Application Support/Arc/Default/GPUCache/blob');
    await makeDir(
      'Library/Application Support/Arc/User Data/Default/GPUCache/blob',
    );
    await makeDir(
      'Library/Application Support/Arc/User Data/component_crx_cache/blob',
    );

    final result = await targets({'pgrep -x Arc': _notRunning()});

    expect(
      result,
      contains(
        '${home.path}/Library/Application Support/Arc/Default/GPUCache/blob',
      ),
    );
    expect(
      result,
      contains(
        '${home.path}/Library/Application Support/Arc/User Data/Default/GPUCache/blob',
      ),
    );
    expect(
      result,
      contains(
        '${home.path}/Library/Application Support/Arc/User Data/component_crx_cache/blob',
      ),
    );
  });

  test(
    'reaches Dia\'s Application Support caches but not the redundant Caches/Dia ones',
    () async {
      await makeDir(
        'Library/Application Support/Dia/User Data/GPUPersistentCache/blob',
      );
      await makeDir(
        'Library/Application Support/Dia/User Data/Default/GPUCache/blob',
      );
      await makeDir('Library/Caches/Dia/User Data/Default/Cache/blob');

      final result = await targets({'pgrep -x Dia': _notRunning()});

      expect(
        result,
        contains(
          '${home.path}/Library/Application Support/Dia/User Data/GPUPersistentCache/blob',
        ),
      );
      expect(
        result,
        contains(
          '${home.path}/Library/Application Support/Dia/User Data/Default/GPUCache/blob',
        ),
      );
      // userEssentials already sweeps ~/Library/Caches/Dia whole (not
      // blanket-protected), so repeating a child of it here would double count.
      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Caches/Dia/User Data/Default/Cache/blob',
          ),
        ),
      );
    },
  );

  test('reaches Brave profile and top-level caches while closed', () async {
    await makeDir(
      'Library/Application Support/BraveSoftware/Brave-Browser/Default/Code Cache/blob',
    );
    await makeDir(
      'Library/Application Support/BraveSoftware/Brave-Browser/Crashpad/completed/blob',
    );

    final result = await targets({'pgrep -x Brave Browser': _notRunning()});

    expect(
      result,
      contains(
        '${home.path}/Library/Application Support/BraveSoftware/Brave-Browser'
        '/Default/Code Cache/blob',
      ),
    );
    expect(
      result,
      contains(
        '${home.path}/Library/Application Support/BraveSoftware/Brave-Browser'
        '/Crashpad/completed/blob',
      ),
    );
  });

  test('reaches Vivaldi profile and top-level caches while closed', () async {
    await makeDir('Library/Application Support/Vivaldi/Default/GPUCache/blob');
    await makeDir('Library/Application Support/Vivaldi/ShaderCache/blob');

    final result = await targets({'pgrep -x Vivaldi': _notRunning()});

    expect(
      result,
      contains(
        '${home.path}/Library/Application Support/Vivaldi/Default/GPUCache/blob',
      ),
    );
    expect(
      result,
      contains(
        '${home.path}/Library/Application Support/Vivaldi/ShaderCache/blob',
      ),
    );
  });

  test('reaches Firefox in both its cache roots while closed', () async {
    await makeDir('Library/Caches/Firefox/blob');
    await makeDir(
      'Library/Application Support/Firefox/Profiles/abc.default/cache2/blob',
    );

    final result = await targets({'pgrep -x Firefox': _notRunning()});

    expect(result, contains('${home.path}/Library/Caches/Firefox/blob'));
    expect(
      result,
      contains(
        '${home.path}/Library/Application Support/Firefox/Profiles/abc.default/cache2/blob',
      ),
    );
  });

  test('a missing home tree proposes nothing and does not throw', () async {
    final result = await targets(const {});
    expect(result, isEmpty);
  });
}
