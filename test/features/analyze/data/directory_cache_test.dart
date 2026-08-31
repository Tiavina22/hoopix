import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_cache.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';

/// Big enough to clear the admission threshold, so these cases are about the
/// rules under test rather than about being too small to record.
DirectoryScan _worthCaching(String path, {int bytes = 50 * 1024 * 1024}) =>
    DirectoryScan(
      path: path,
      status: DirectoryScanStatus.loaded,
      entries: [
        AnalyzeEntry(
          path: '$path/big',
          name: 'big',
          isDirectory: true,
          sizeBytes: bytes,
        ),
      ],
      totalBytes: bytes,
    );

void main() {
  late Directory cacheDir;
  late Directory scanned;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('hoopix_dircache_');
    scanned = await Directory.systemTemp.createTemp('hoopix_scanned_');
  });

  tearDown(() async {
    for (final directory in [cacheDir, scanned]) {
      if (directory.existsSync()) await directory.delete(recursive: true);
    }
  });

  DirectoryCache cache() => DirectoryCache(cacheDirectory: cacheDir.path);

  File entryFile() => Directory('${cacheDir.path}/analyzer')
      .listSync()
      .whereType<File>()
      .single;

  test('a recorded listing comes back on the next visit', () {
    cache().store(scanned.path, _worthCaching(scanned.path), deduped: false);

    final loaded = cache().load(scanned.path);

    expect(loaded, isNotNull);
    expect(loaded!.entries.single.name, 'big');
    expect(loaded.totalBytes, 50 * 1024 * 1024);
  });

  test('a directory too small to be worth it is never recorded', () {
    cache().store(
      scanned.path,
      _worthCaching(scanned.path, bytes: 1024),
      deduped: false,
    );

    expect(cache().load(scanned.path), isNull);
    expect(Directory('${cacheDir.path}/analyzer').existsSync(), isFalse);
  });

  test('a total that depended on hardlink dedup is refused', () {
    // Replaying it later could report a size the directory never had, since
    // which link paid depends on the order the tree was walked.
    cache().store(scanned.path, _worthCaching(scanned.path), deduped: true);

    expect(cache().load(scanned.path), isNull);
  });

  test('an unfinished scan is not recorded', () {
    cache().store(
      scanned.path,
      DirectoryScan(
        path: scanned.path,
        status: DirectoryScanStatus.scanning,
        totalBytes: 50 * 1024 * 1024,
      ),
      deduped: false,
    );

    expect(cache().load(scanned.path), isNull);
  });

  test('an entry from another schema is dropped, not reused', () {
    cache().store(scanned.path, _worthCaching(scanned.path), deduped: false);
    final file = entryFile();
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    file.writeAsStringSync(jsonEncode({...json, 'schemaVersion': 99}));

    expect(cache().load(scanned.path), isNull);
    expect(file.existsSync(), isFalse);
  });

  test('an entry past the TTL is dropped', () {
    cache().store(scanned.path, _worthCaching(scanned.path), deduped: false);
    final file = entryFile();
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    file.writeAsStringSync(
      jsonEncode({
        ...json,
        'scannedAt': DateTime.now()
            .subtract(const Duration(days: 8))
            .toIso8601String(),
      }),
    );

    expect(cache().load(scanned.path), isNull);
    expect(file.existsSync(), isFalse);
  });

  test('an entry for a directory that is gone is dropped', () async {
    cache().store(scanned.path, _worthCaching(scanned.path), deduped: false);
    final file = entryFile();
    await scanned.delete(recursive: true);

    expect(cache().load(scanned.path), isNull);
    // Nothing will ever refresh it, so it does not sit there for a full TTL.
    expect(file.existsSync(), isFalse);
  });

  test('a corrupt entry reads as a miss instead of throwing', () {
    cache().store(scanned.path, _worthCaching(scanned.path), deduped: false);
    entryFile().writeAsStringSync('{ not json');

    expect(cache().load(scanned.path), isNull);
  });

  test('a modified directory is still reused inside the reuse window', () {
    cache().store(scanned.path, _worthCaching(scanned.path), deduped: false);
    final file = entryFile();
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    // Modified well past the grace, but scanned minutes ago: macOS bumps
    // directory mtimes for changes that alter nothing worth rescanning for.
    file.writeAsStringSync(
      jsonEncode({
        ...json,
        'directoryModified': DateTime.now()
            .subtract(const Duration(days: 2))
            .toIso8601String(),
      }),
    );

    expect(cache().load(scanned.path), isNotNull);
  });

  test('a modified directory is refused once the entry is old', () {
    cache().store(scanned.path, _worthCaching(scanned.path), deduped: false);
    final file = entryFile();
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    file.writeAsStringSync(
      jsonEncode({
        ...json,
        'scannedAt': DateTime.now()
            .subtract(const Duration(days: 2))
            .toIso8601String(),
        'directoryModified': DateTime.now()
            .subtract(const Duration(days: 5))
            .toIso8601String(),
      }),
    );

    // Strict load refuses it...
    expect(cache().load(scanned.path), isNull);
    // ...but first paint still shows it while a real scan runs behind.
    expect(cache().load(scanned.path, allowStale: true), isNotNull);
  });

  test('first paint stops trusting an entry past the stale window', () {
    cache().store(scanned.path, _worthCaching(scanned.path), deduped: false);
    final file = entryFile();
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    file.writeAsStringSync(
      jsonEncode({
        ...json,
        'scannedAt': DateTime.now()
            .subtract(const Duration(days: 4))
            .toIso8601String(),
      }),
    );

    expect(cache().load(scanned.path, allowStale: true), isNull);
  });

  test('caching is off when there is no cache directory', () {
    final none = DirectoryCache(cacheDirectory: null)
      ..store(scanned.path, _worthCaching(scanned.path), deduped: false);

    expect(none.load(scanned.path), isNull);
  });
}
