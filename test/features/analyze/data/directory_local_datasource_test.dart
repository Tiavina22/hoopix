import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_local_datasource.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';

import '../../../support/fake_process_runner.dart';

/// `du -s -k` prints one `<blocks>\t<path>` line; `-k` blocks are 1024 bytes.
String _duLine(int kilobytes, String path) => '$kilobytes\t$path\n';

AnalyzeEntry _entry(DirectoryScan scan, String name) =>
    scan.entries.firstWhere((entry) => entry.name == name);

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hoopix_analyze_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('sizes files from stat and directories from du', () async {
    await File('${root.path}/small.txt').writeAsString('x' * 100);
    await Directory('${root.path}/photos').create();

    final runner = FakeProcessRunner({
      'du -skPx ${root.path}/photos': ProcessResult.success(
        _duLine(500, '${root.path}/photos'),
      ),
    });

    final scans = await DirectoryLocalDataSource(runner).watch(root.path).toList();

    // First emission is the listing itself: the file already carries its
    // final size, the directory is still pending.
    expect(scans.first.status, DirectoryScanStatus.scanning);
    expect(_entry(scans.first, 'small.txt').sizeBytes, 100);
    expect(_entry(scans.first, 'photos').sizeBytes, isNull);

    final last = scans.last;
    expect(last.status, DirectoryScanStatus.loaded);
    expect(_entry(last, 'photos').sizeBytes, 500 * 1024);
    expect(last.totalBytes, 500 * 1024 + 100);
    // Sorted by size descending: the 500 KB directory outranks the file.
    expect(last.entries.map((entry) => entry.name), ['photos', 'small.txt']);
  });

  test('keeps a du total that came with a non-zero exit', () async {
    // The `~/Library` case: `du` exits 1 because some descendant is
    // unreadable, but the total it printed is still the right number.
    await Directory('${root.path}/library').create();

    final runner = FakeProcessRunner({
      'du -skPx ${root.path}/library': ProcessResult.failure(
        ProcessFailure.nonZeroExit('du', 1, 'du: ...: Operation not permitted'),
        stdout: _duLine(31720772, '${root.path}/library'),
      ),
    });

    final scans = await DirectoryLocalDataSource(runner).watch(root.path).toList();

    expect(scans.last.status, DirectoryScanStatus.loaded);
    expect(_entry(scans.last, 'library').sizeBytes, 31720772 * 1024);
  });

  test('a timed-out probe leaves one size unknown without failing the rest', () async {
    await Directory('${root.path}/fast').create();
    await Directory('${root.path}/slow').create();

    final runner = FakeProcessRunner({
      'du -skPx ${root.path}/fast': ProcessResult.success(
        _duLine(64, '${root.path}/fast'),
      ),
      'du -skPx ${root.path}/slow': ProcessResult.failure(
        ProcessFailure.timedOut('du', const Duration(seconds: 60)),
      ),
    });

    final scans = await DirectoryLocalDataSource(runner).watch(root.path).toList();

    final last = scans.last;
    expect(last.status, DirectoryScanStatus.loaded);
    expect(_entry(last, 'fast').sizeBytes, 64 * 1024);
    expect(_entry(last, 'slow').sizeBytes, isNull);
    // Unknown sizes sort last so rows settle downward rather than reshuffle.
    expect(last.entries.map((entry) => entry.name), ['fast', 'slow']);
  });

  test('an empty directory loads with no entries', () async {
    final scans = await DirectoryLocalDataSource(
      FakeProcessRunner(const {}),
    ).watch(root.path).toList();

    expect(scans, hasLength(1));
    expect(scans.single.status, DirectoryScanStatus.loaded);
    expect(scans.single.entries, isEmpty);
    expect(scans.single.isEmpty, isTrue);
  });

  test('symlinks are neither listed nor sized', () async {
    await File('${root.path}/real.txt').writeAsString('x' * 10);
    await Link('${root.path}/alias.txt').create('${root.path}/real.txt');

    final scans = await DirectoryLocalDataSource(
      FakeProcessRunner(const {}),
    ).watch(root.path).toList();

    expect(scans.last.entries.map((entry) => entry.name), ['real.txt']);
  });

  test('reports permission denied when the directory itself is unreadable', () async {
    final locked = await Directory('${root.path}/locked').create();
    await Process.run('chmod', ['000', locked.path]);
    addTearDown(() => Process.run('chmod', ['755', locked.path]));

    final scans = await DirectoryLocalDataSource(
      FakeProcessRunner(const {}),
    ).watch(locked.path).toList();

    expect(scans.single.status, DirectoryScanStatus.permissionDenied);
    expect(scans.single.entries, isEmpty);
  });

  test('reports a failure for a path that does not exist', () async {
    final scans = await DirectoryLocalDataSource(
      FakeProcessRunner(const {}),
    ).watch('${root.path}/missing').toList();

    expect(scans.single.status, DirectoryScanStatus.failed);
  });
}
