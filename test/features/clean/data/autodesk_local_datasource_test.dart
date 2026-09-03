import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/apps_and_utilities_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/autodesk_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _running() => ProcessResult.success('123');

const _currentHash = '0123456789abcdef0123456789abcdef01234567';
const _oldHash = 'fedcba9876543210fedcba9876543210fedcba98';
const _newerHash = 'aaaabbbbccccddddeeeeffff0000111122223333';

void main() {
  late Directory home;
  late Map<String, ProcessResult> responses;

  String productionDir() =>
      '${home.path}/Library/Application Support/Autodesk/webdeploy/production';

  setUp(() async {
    // Resolved to its physical path: /var is a symlink to /private/var on
    // macOS, and the production root must be its own physical path.
    final temp = await Directory.systemTemp.createTemp('hoopix_autodesk_home_');
    home = Directory(await temp.resolveSymbolicLinks());
    // Every Autodesk process absent unless a test says otherwise.
    responses = {
      for (final name in [
        'AcCoreConsole',
        'ADPClientService',
        'streamer',
        'Fusion Client Downloader',
        'Fusion 360 Client Downloader',
      ])
        'pgrep -x $name': _notRunning(),
      for (final pattern in [
        'com.autodesk.',
        '/AcCoreConsole',
        '/ADPClientService',
        '/streamer',
        'Autodesk Fusion',
        'Fusion 360',
        'Fusion360',
      ])
        'pgrep -f $pattern': _notRunning(),
    };
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  /// Builds one version directory holding a Fusion bundle, and registers
  /// the plist answers its evidence chain needs.
  Future<String> makeVersionDir(
    String hash, {
    required String version,
    String bundleName = 'Autodesk Fusion.app',
    String executable = 'Autodesk Fusion',
    String bundleId = 'com.autodesk.fusion360',
  }) async {
    final dir = '${productionDir()}/$hash';
    final app = '$dir/$bundleName';
    await Directory('$app/Contents/MacOS').create(recursive: true);
    final plist = '$app/Contents/Info.plist';
    await File(plist).create(recursive: true);
    final executablePath = '$app/Contents/MacOS/$executable';
    await File(executablePath).create(recursive: true);
    await Process.run('chmod', ['+x', executablePath]);

    responses['/usr/bin/plutil -extract CFBundleIdentifier raw $plist'] =
        ProcessResult.success(bundleId);
    responses['/usr/bin/plutil -extract CFBundleVersion raw $plist'] =
        ProcessResult.success(version);
    responses['/usr/bin/plutil -extract CFBundleExecutable raw $plist'] =
        ProcessResult.success(executable);
    return dir;
  }

  /// Points `production/Autodesk Fusion.app` at [target] as a symlink.
  Future<void> makeCurrentLink(String target) =>
      Link('${productionDir()}/Autodesk Fusion.app').create(target);

  AutodeskLocalDataSource source() => AutodeskLocalDataSource(
    home: home.path,
    guard: ProcessGuard(FakeProcessRunner(responses)),
    probe: FakeProcessRunner(responses),
  );

  Future<CleanSectionTargets> enumerate() => source().enumerate();

  test('section name matches the constant Apps & utilities uses', () async {
    final result = await enumerate();
    expect(result.section, AppsAndUtilitiesLocalDataSource.appsAndUtilities);
  });

  group('caches', () {
    test('proposes the children of each com.autodesk.* cache', () async {
      await Directory(
        '${home.path}/Library/Caches/com.autodesk.fusion360/blob',
      ).create(recursive: true);

      final result = await enumerate();

      expect(
        result.paths,
        contains('${home.path}/Library/Caches/com.autodesk.fusion360/blob'),
      );
    });

    test('proposes an empty cache directory itself', () async {
      await Directory(
        '${home.path}/Library/Caches/com.autodesk.AutoCAD',
      ).create(recursive: true);

      final result = await enumerate();

      expect(result.paths, [
        '${home.path}/Library/Caches/com.autodesk.AutoCAD',
      ]);
    });

    test('leaves other vendors alone', () async {
      await Directory(
        '${home.path}/Library/Caches/com.adobe.something/blob',
      ).create(recursive: true);

      expect((await enumerate()).paths, isEmpty);
    });

    test('a cache carries no revalidator, only the process recheck', () async {
      await Directory(
        '${home.path}/Library/Caches/com.autodesk.AutoCAD',
      ).create(recursive: true);

      final result = await enumerate();
      final path = '${home.path}/Library/Caches/com.autodesk.AutoCAD';

      expect(result.revalidatorKeys.containsKey(path), isFalse);
      expect(
        result.recheckProcessGuards[path]?.exactNames,
        contains('AcCoreConsole'),
      );
    });
  });

  group('Fusion old bundles', () {
    test('proposes only versions older than the current one', () async {
      final oldDir = await makeVersionDir(_oldHash, version: '2.0.19042');
      await makeVersionDir(_currentHash, version: '2.0.20000');
      await makeVersionDir(_newerHash, version: '2.0.21000');
      await makeCurrentLink('${productionDir()}/$_currentHash');

      final result = await enumerate();

      expect(result.paths, [oldDir]);
      expect(
        result.revalidatorKeys[oldDir],
        AutodeskLocalDataSource.revalidatorKey,
      );
    });

    test(
      'resolves a link that points at the bundle inside a version',
      () async {
        final oldDir = await makeVersionDir(_oldHash, version: '2.0.19042');
        await makeVersionDir(_currentHash, version: '2.0.20000');
        await makeCurrentLink(
          '${productionDir()}/$_currentHash/Autodesk Fusion.app',
        );

        expect((await enumerate()).paths, [oldDir]);
      },
    );

    test('proposes nothing when there is no current link at all', () async {
      await makeVersionDir(_oldHash, version: '2.0.19042');
      await makeVersionDir(_currentHash, version: '2.0.20000');

      expect((await enumerate()).paths, isEmpty);
    });

    test('keeps a directory whose name is not 40 hex characters', () async {
      await makeVersionDir('not-a-hash-directory', version: '2.0.19042');
      await makeVersionDir(_currentHash, version: '2.0.20000');
      await makeCurrentLink('${productionDir()}/$_currentHash');

      expect((await enumerate()).paths, isEmpty);
    });

    test('keeps a directory whose bundle id is not Fusion', () async {
      await makeVersionDir(
        _oldHash,
        version: '2.0.19042',
        bundleId: 'com.autodesk.autocad',
      );
      await makeVersionDir(_currentHash, version: '2.0.20000');
      await makeCurrentLink('${productionDir()}/$_currentHash');

      expect((await enumerate()).paths, isEmpty);
    });

    test('keeps a directory holding two Fusion bundles', () async {
      final ambiguous = await makeVersionDir(_oldHash, version: '2.0.19042');
      await Directory(
        '$ambiguous/Autodesk Fusion 360.app/Contents/MacOS',
      ).create(recursive: true);
      await makeVersionDir(_currentHash, version: '2.0.20000');
      await makeCurrentLink('${productionDir()}/$_currentHash');

      expect((await enumerate()).paths, isEmpty);
    });

    test('keeps a directory whose executable is missing', () async {
      final oldDir = await makeVersionDir(_oldHash, version: '2.0.19042');
      await File(
        '$oldDir/Autodesk Fusion.app/Contents/MacOS/Autodesk Fusion',
      ).delete();
      await makeVersionDir(_currentHash, version: '2.0.20000');
      await makeCurrentLink('${productionDir()}/$_currentHash');

      expect((await enumerate()).paths, isEmpty);
    });

    test('keeps a version equal to the current one', () async {
      await makeVersionDir(_oldHash, version: '2.0.20000');
      await makeVersionDir(_currentHash, version: '2.0.20000');
      await makeCurrentLink('${productionDir()}/$_currentHash');

      expect((await enumerate()).paths, isEmpty);
    });

    test('compares versions numerically, not lexically', () async {
      // 2.0.9000 is older than 2.0.20000 numerically but larger as text.
      final oldDir = await makeVersionDir(_oldHash, version: '2.0.9000');
      await makeVersionDir(_currentHash, version: '2.0.20000');
      await makeCurrentLink('${productionDir()}/$_currentHash');

      expect((await enumerate()).paths, [oldDir]);
    });
  });

  test('proposes nothing while any Autodesk process is running', () async {
    await Directory(
      '${home.path}/Library/Caches/com.autodesk.AutoCAD',
    ).create(recursive: true);
    responses['pgrep -x ADPClientService'] = _running();

    expect((await enumerate()).paths, isEmpty);
  });

  group('stillEligible', () {
    test('holds while nothing changed', () async {
      final oldDir = await makeVersionDir(_oldHash, version: '2.0.19042');
      await makeVersionDir(_currentHash, version: '2.0.20000');
      await makeCurrentLink('${productionDir()}/$_currentHash');

      final datasource = source();
      await datasource.enumerate();

      expect(await datasource.stillEligible(oldDir), isTrue);
    });

    test('refuses once the updater switched the current version', () async {
      final oldDir = await makeVersionDir(_oldHash, version: '2.0.19042');
      await makeVersionDir(_currentHash, version: '2.0.20000');
      final newerDir = await makeVersionDir(_newerHash, version: '2.0.21000');
      await makeCurrentLink('${productionDir()}/$_currentHash');

      final datasource = source();
      await datasource.enumerate();

      await Link('${productionDir()}/Autodesk Fusion.app').delete();
      await Link('${productionDir()}/Autodesk Fusion.app').create(newerDir);

      expect(await datasource.stillEligible(oldDir), isFalse);
    });

    test('refuses once the candidate is gone', () async {
      final oldDir = await makeVersionDir(_oldHash, version: '2.0.19042');
      await makeVersionDir(_currentHash, version: '2.0.20000');
      await makeCurrentLink('${productionDir()}/$_currentHash');

      final datasource = source();
      await datasource.enumerate();
      await Directory(oldDir).delete(recursive: true);

      expect(await datasource.stillEligible(oldDir), isFalse);
    });

    test('refuses a path that was never scanned', () async {
      await makeVersionDir(_currentHash, version: '2.0.20000');
      await makeCurrentLink('${productionDir()}/$_currentHash');

      final datasource = source();
      await datasource.enumerate();

      expect(
        await datasource.stillEligible('${productionDir()}/$_oldHash'),
        isFalse,
      );
    });
  });

  test('a missing Autodesk tree does not throw', () async {
    expect((await enumerate()).paths, isEmpty);
  });
}
