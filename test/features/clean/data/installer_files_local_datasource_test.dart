import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/installer_files_local_datasource.dart';

/// Fakes `zipinfo`/`unzip` responses while letting `stat` run for real
/// against the temp fixtures this test creates — cheaper than inventing a
/// fake identity string for every candidate file, and it exercises the
/// real `dev:inode:mtime` parsing the same way production does.
class _HybridProcessRunner extends ProcessRunner {
  _HybridProcessRunner(this._responses);

  final Map<String, ProcessResult> _responses;
  static const _real = ProcessRunner(timeout: Duration(seconds: 5));

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    if (executable == 'stat') return _real.run(executable, arguments);
    final key = [executable, ...arguments].join(' ');
    return _responses[key] ??
        ProcessResult.failure(
          ProcessFailure.notFound(executable, 'no fake response for `$key`'),
        );
  }
}

void main() {
  late Directory home;
  late Directory sharedStub;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_installer_home_');
    sharedStub = await Directory.systemTemp.createTemp(
      'hoopix_installer_shared_',
    );
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
    if (sharedStub.existsSync()) await sharedStub.delete(recursive: true);
  });

  InstallerFilesLocalDataSource source({
    Map<String, ProcessResult> zipResponses = const {},
  }) => InstallerFilesLocalDataSource(
    home: home.path,
    probe: _HybridProcessRunner(zipResponses),
    // `/Users/Shared` is a fixed, non-home absolute root Mole itself
    // scans; redirecting it into an isolated temp dir keeps the test from
    // ever reading the real machine's own `/Users/Shared`.
    directory: (path) => path.startsWith('/Users/Shared')
        ? Directory(
            '${sharedStub.path}${path.substring('/Users/Shared'.length)}',
          )
        : Directory(path),
  );

  Future<File> createFile(String relative, {String content = 'x'}) async {
    final file = File('${home.path}/$relative');
    await file.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  test('section name is Installers', () async {
    final result = await source().enumerate();
    expect(result.section, 'Installers');
  });

  test('finds a direct-extension file at depth 1 and depth 2', () async {
    await createFile('Downloads/Xcode.dmg');
    await createFile('Downloads/nested/Update.pkg');

    final result = await source().enumerate();

    expect(result.paths, contains('${home.path}/Downloads/Xcode.dmg'));
    expect(result.paths, contains('${home.path}/Downloads/nested/Update.pkg'));
  });

  test('does not descend past depth 2', () async {
    await createFile('Downloads/a/b/TooDeep.dmg');

    final result = await source().enumerate();

    expect(result.paths, isEmpty);
  });

  test('ignores a non-installer extension', () async {
    await createFile('Downloads/notes.txt');

    final result = await source().enumerate();

    expect(result.paths, isEmpty);
  });

  test('skips a symlinked file', () async {
    final target = await createFile('Documents/Real.dmg');
    await Process.run('ln', [
      '-s',
      target.path,
      '${home.path}/Downloads/Linked.dmg',
    ]);

    final result = await source().enumerate();

    expect(result.paths, contains(target.path));
    expect(result.paths, isNot(contains('${home.path}/Downloads/Linked.dmg')));
  });

  test('does not follow a symlinked directory', () async {
    final realDir = await Directory(
      '${home.path}/Elsewhere',
    ).create(recursive: true);
    await createFile('Elsewhere/Hidden.dmg');
    await Process.run('ln', [
      '-s',
      realDir.path,
      '${home.path}/Downloads/link-dir',
    ]);

    final result = await source().enumerate();

    expect(result.paths, isNot(contains('${home.path}/Elsewhere/Hidden.dmg')));
  });

  test(
    'scans the fixed /Users/Shared root through the directory seam',
    () async {
      final file = File('${sharedStub.path}/Installer.pkg');
      await file.create(recursive: true);
      await file.writeAsString('x');

      final result = await source().enumerate();

      expect(result.paths, contains(file.path));
    },
  );

  test('missing scan roots are skipped without throwing', () async {
    expect(source().enumerate(), completes);
  });

  test('excludes a zip with no installer payload inside', () async {
    final zip = await createFile('Downloads/data.zip');

    final result = await source(
      zipResponses: {
        'zipinfo -1 ${zip.path}': ProcessResult.success(
          'readme.txt\nnotes.csv\n',
        ),
      },
    ).enumerate();

    expect(result.paths, isEmpty);
  });

  test('includes a zip whose listing shows an installer payload', () async {
    final zip = await createFile('Downloads/bundle.zip');

    final result = await source(
      zipResponses: {
        'zipinfo -1 ${zip.path}': ProcessResult.success(
          'readme.txt\nMyApp.app/Contents/Info.plist\n',
        ),
      },
    ).enumerate();

    expect(result.paths, contains(zip.path));
  });

  test('falls back to unzip -Z -1 when zipinfo is unavailable', () async {
    final zip = await createFile('Downloads/bundle.zip');

    final result = await source(
      zipResponses: {
        'unzip -Z -1 ${zip.path}': ProcessResult.success('installer.pkg\n'),
      },
    ).enumerate();

    expect(result.paths, contains(zip.path));
  });

  test(
    'every eligible path carries this datasource as its revalidator',
    () async {
      await createFile('Downloads/Xcode.dmg');

      final result = await source().enumerate();

      expect(
        result.revalidatorKeys,
        equals({
          for (final path in result.paths)
            path: InstallerFilesLocalDataSource.revalidatorKey,
        }),
      );
      expect(result.paths, isNotEmpty);
    },
  );

  group('stillEligible', () {
    test('true for a path found at scan time, unchanged since', () async {
      await createFile('Downloads/Xcode.dmg');
      final ds = source();
      final result = await ds.enumerate();

      expect(await ds.stillEligible(result.paths.single), isTrue);
    });

    test('false once the file has been removed', () async {
      final file = await createFile('Downloads/Xcode.dmg');
      final ds = source();
      final result = await ds.enumerate();
      await file.delete();

      expect(await ds.stillEligible(result.paths.single), isFalse);
    });

    test(
      'false once the file has been replaced with different content',
      () async {
        final file = await createFile('Downloads/Xcode.dmg');
        final ds = source();
        final result = await ds.enumerate();
        // A fresh download landing on the same name changes the inode.
        await file.delete();
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        await file.create();
        await file.writeAsString('replaced');

        expect(await ds.stillEligible(result.paths.single), isFalse);
      },
    );

    test('false for a path this datasource never proposed', () async {
      expect(await source().stillEligible('${home.path}/nope.dmg'), isFalse);
    });
  });
}
