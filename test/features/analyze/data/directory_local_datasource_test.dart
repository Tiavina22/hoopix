import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/directory_scanner.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_cache.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_local_datasource.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';

/// Replays a scripted walk instead of touching the disk. The walk itself is
/// native (`macos/Runner/DirectoryScanChannel.swift`); what is under test
/// here is how its events become the snapshots the screen renders.
class _FakeScanner implements DirectoryScanner {
  _FakeScanner(this.events);

  final List<ScanEvent> events;
  final List<String> scanned = [];

  @override
  Stream<ScanEvent> scan(String path) {
    scanned.add(path);
    return Stream.fromIterable(events);
  }
}

/// Caching off: these cases are about turning scan events into snapshots.
/// The cache has its own tests.
DirectoryCache _noCache() => DirectoryCache(cacheDirectory: null);

AnalyzeEntry _entry(DirectoryScan scan, String name) =>
    scan.entries.firstWhere((entry) => entry.name == name);

ScanEntry _file(String path, int size) =>
    ScanEntry(path: path, isDirectory: false, sizeBytes: size, accessed: null);

ScanEntry _directory(String path) =>
    ScanEntry(path: path, isDirectory: true, sizeBytes: null, accessed: null);

void main() {
  test('files arrive sized, directories fill in afterwards', () async {
    final scanner = _FakeScanner([
      _file('/root/small.txt', 100),
      _directory('/root/photos'),
      const ScanListed(1),
      const ScanSize('/root/photos', 512000),
      const ScanComplete(),
    ]);

    final scans = await DirectoryLocalDataSource(scanner, _noCache()).watch('/root').toList();

    expect(scanner.scanned, ['/root']);

    // First frame: the file is final, the directory is still measuring.
    final listed = scans.first;
    expect(listed.status, DirectoryScanStatus.scanning);
    expect(_entry(listed, 'small.txt').sizeBytes, 100);
    expect(_entry(listed, 'photos').sizeBytes, isNull);

    final last = scans.last;
    expect(last.status, DirectoryScanStatus.loaded);
    expect(_entry(last, 'photos').sizeBytes, 512000);
    expect(last.totalBytes, 512100);
    // Sorted by size descending.
    expect(last.entries.map((entry) => entry.name), ['photos', 'small.txt']);
  });

  test('a directory with no children loads immediately', () async {
    final scans = await DirectoryLocalDataSource(
      _FakeScanner([const ScanListed(0), const ScanComplete()]),
      _noCache(),
    ).watch('/empty').toList();

    expect(scans.first.status, DirectoryScanStatus.loaded);
    expect(scans.first.entries, isEmpty);
    expect(scans.first.isEmpty, isTrue);
  });

  test('an unreadable directory reports permission denied', () async {
    final scans = await DirectoryLocalDataSource(
      // EACCES.
      _FakeScanner([const ScanFailed('Permission denied', 13)]),
      _noCache(),
    ).watch('/locked').toList();

    expect(scans.single.status, DirectoryScanStatus.permissionDenied);
    expect(scans.single.entries, isEmpty);
  });

  test('any other failure is reported as a failure, not a refusal', () async {
    final scans = await DirectoryLocalDataSource(
      // ENOENT.
      _FakeScanner([const ScanFailed('No such file or directory', 2)]),
      _noCache(),
    ).watch('/missing').toList();

    expect(scans.single.status, DirectoryScanStatus.failed);
  });

  test('sizes still pending sort last so rows settle downward', () async {
    final scans = await DirectoryLocalDataSource(
      _FakeScanner([
        _directory('/root/slow'),
        _directory('/root/fast'),
        const ScanListed(2),
        const ScanSize('/root/fast', 64000),
        const ScanComplete(),
      ]),
      _noCache(),
    ).watch('/root').toList();

    // `slow` never reported a size; it stays visible, below the sized one.
    final last = scans.last;
    expect(last.entries.map((entry) => entry.name), ['fast', 'slow']);
    expect(_entry(last, 'slow').sizeBytes, isNull);
  });


  test('caps the shown list at 30 while the total stays true', () async {
    final entries = [
      for (var i = 0; i < 40; i++) _file('/root/f$i', 40 - i),
    ];
    final scanner = _FakeScanner([
      ...entries,
      const ScanListed(0),
      const ScanComplete(),
    ]);

    final scans = await DirectoryLocalDataSource(scanner, _noCache())
        .watch('/root')
        .toList();

    final last = scans.last;
    expect(last.entries, hasLength(30));
    // The biggest 30 are kept, in order.
    expect(last.entries.first.name, 'f0');
    expect(last.entries.last.name, 'f29');
    // The total is every file's size, not just the 30 shown.
    final expectedTotal = List.generate(40, (i) => 40 - i).reduce((a, b) => a + b);
    expect(last.totalBytes, expectedTotal);
  });

  test('capEntries: false returns every entry, uncapped', () async {
    final entries = [
      for (var i = 0; i < 40; i++) _file('/root/f$i', 40 - i),
    ];
    final scanner = _FakeScanner([
      ...entries,
      const ScanListed(0),
      const ScanComplete(),
    ]);

    final scans = await DirectoryLocalDataSource(scanner, _noCache())
        .watch('/root', capEntries: false)
        .toList();

    expect(scans.last.entries, hasLength(40));
  });

  test('carries the last-access time through to the row', () async {
    final accessed = DateTime(2026, 3, 14);
    final scans = await DirectoryLocalDataSource(
      _FakeScanner([
        ScanEntry(
          path: '/root/old.dmg',
          isDirectory: false,
          sizeBytes: 10,
          accessed: accessed,
        ),
        const ScanListed(0),
        const ScanComplete(),
      ]),
      _noCache(),
    ).watch('/root').toList();

    expect(_entry(scans.last, 'old.dmg').accessed, accessed);
  });
}
