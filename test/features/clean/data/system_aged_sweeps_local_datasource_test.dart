import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/data/datasources/system_aged_sweeps_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/system_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hoopix_system_sweeps_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// Redirects each real sweep root at a directory inside the temp tree,
  /// so the sweeps can be exercised without touching the real system.
  Directory fakeRoot(String path) {
    const roots = {
      '/Library/Caches': 'caches',
      '/Library/Logs/DiagnosticReports': 'diagnostics',
      '/private/var/log': 'varlog',
      '/Library/Logs/Adobe': 'adobe',
      '/Library/Logs/CreativeCloud': 'creativecloud',
    };
    for (final entry in roots.entries) {
      if (path == entry.key) return Directory('${root.path}/${entry.value}');
      if (path.startsWith('${entry.key}/')) {
        return Directory(
          '${root.path}/${entry.value}${path.substring(entry.key.length)}',
        );
      }
    }
    return Directory(path);
  }

  Future<File> makeFile(String relative, {required int ageDays}) async {
    final file = File('${root.path}/$relative');
    await file.create(recursive: true);
    final stamp = DateTime.now().subtract(Duration(days: ageDays));
    final formatted =
        '${stamp.year.toString().padLeft(4, '0')}'
        '${stamp.month.toString().padLeft(2, '0')}'
        '${stamp.day.toString().padLeft(2, '0')}'
        '${stamp.hour.toString().padLeft(2, '0')}'
        '${stamp.minute.toString().padLeft(2, '0')}';
    await Process.run('touch', ['-t', formatted, file.path]);
    return file;
  }

  CleanSectionTargets enumerate({int visitBudget = 20000}) =>
      SystemAgedSweepsLocalDataSource(
        directory: fakeRoot,
        visitBudget: visitBudget,
      ).enumerate();

  /// The path the datasource reports for a file created at [relative]
  /// inside the temp tree — it walks the redirected directories, so the
  /// paths it returns are the temp ones.
  String reported(String relative) => '${root.path}/$relative';

  test('section name matches the constant System uses', () {
    expect(enumerate().section, SystemLocalDataSource.system);
  });

  group('/Library/Caches', () {
    test('sweeps stale .cache, .tmp and .log files', () async {
      await makeFile('caches/a.cache', ageDays: 30);
      await makeFile('caches/b.tmp', ageDays: 30);
      await makeFile('caches/c.log', ageDays: 30);

      final result = enumerate();

      expect(
        result.paths,
        containsAll([
          reported('caches/a.cache'),
          reported('caches/b.tmp'),
          reported('caches/c.log'),
        ]),
      );
    });

    test('leaves files younger than the 7-day retention', () async {
      await makeFile('caches/fresh.cache', ageDays: 2);

      expect(enumerate().paths, isEmpty);
    });

    test('leaves a name that matches no pattern', () async {
      await makeFile('caches/keep.db', ageDays: 30);

      expect(enumerate().paths, isEmpty);
    });

    test('goes five levels deep but no further', () async {
      await makeFile('caches/a/b/c/d/deep.cache', ageDays: 30);
      await makeFile('caches/a/b/c/d/e/too-deep.cache', ageDays: 30);

      final result = enumerate();

      expect(result.paths, [reported('caches/a/b/c/d/deep.cache')]);
    });

    test('routes to the Trash, never to the privileged channel', () async {
      await makeFile('caches/a.cache', ageDays: 30);

      final result = enumerate();

      expect(result.paths, isNotEmpty);
      expect(result.privilegedDeletionPaths, isEmpty);
    });
  });

  group('root-owned log roots', () {
    test('sweep every stale file and require privileges', () async {
      await makeFile('diagnostics/crash.ips', ageDays: 30);
      await makeFile('varlog/system.log', ageDays: 30);
      await makeFile('adobe/install.log', ageDays: 30);
      await makeFile('creativecloud/cc.log', ageDays: 30);

      final result = enumerate();

      final expected = [
        reported('diagnostics/crash.ips'),
        reported('varlog/system.log'),
        reported('adobe/install.log'),
        reported('creativecloud/cc.log'),
      ];
      expect(result.paths, containsAll(expected));
      expect(result.privilegedDeletionPaths, containsAll(expected));
    });

    test('crash reports go one level deep only', () async {
      await makeFile('diagnostics/nested/crash.ips', ageDays: 30);

      expect(enumerate().paths, isEmpty);
    });

    test('/private/var/log only sweeps its three extensions', () async {
      await makeFile('varlog/keep.txt', ageDays: 30);
      await makeFile('varlog/old.gz', ageDays: 30);
      await makeFile('varlog/old.asl', ageDays: 30);

      final result = enumerate();

      expect(
        result.paths,
        unorderedEquals([
          reported('varlog/old.gz'),
          reported('varlog/old.asl'),
        ]),
      );
    });
  });

  test('never proposes a directory, however old', () async {
    final dir = Directory('${root.path}/caches/stale.cache');
    await dir.create(recursive: true);
    await Process.run('touch', ['-t', '202001010000', dir.path]);

    expect(enumerate().paths, isEmpty);
  });

  test('never proposes or follows a symlink', () async {
    final target = await makeFile('outside/secret.cache', ageDays: 30);
    await Directory('${root.path}/caches/dir').create(recursive: true);
    await Link('${root.path}/caches/link.cache').create(target.path);
    await Link('${root.path}/caches/dirlink').create('${root.path}/outside');

    final result = enumerate();

    expect(result.paths, isEmpty);
  });

  test('stops once the visit budget is spent', () async {
    for (var index = 0; index < 20; index++) {
      await makeFile('caches/file$index.cache', ageDays: 30);
    }

    final result = enumerate(visitBudget: 5);

    expect(result.paths.length, lessThan(20));
  });

  test('a missing root is skipped without throwing', () {
    expect(enumerate().paths, isEmpty);
  });
}
