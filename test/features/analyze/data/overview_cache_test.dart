import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/analyze/data/datasources/overview_cache.dart';

void main() {
  late Directory cacheDir;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('hoopix_cache_');
  });

  tearDown(() async {
    if (cacheDir.existsSync()) await cacheDir.delete(recursive: true);
  });

  File store() => File('${cacheDir.path}/overview_sizes.json');

  OverviewCache cache() => OverviewCache(cacheDirectory: cacheDir.path);

  test('a stored size is readable by the next instance', () {
    cache().store('/Users/tester/Library', 4096);

    expect(cache().sizeOf('/Users/tester/Library'), 4096);
  });

  test('an unknown path has no remembered size', () {
    expect(cache().sizeOf('/nope'), isNull);
  });

  test('entries past the 7-day TTL are ignored', () {
    store().parent.createSync(recursive: true);
    store().writeAsStringSync(
      jsonEncode({
        '/stale': {
          'size': 999,
          'updated': DateTime.now()
              .subtract(const Duration(days: 8))
              .toIso8601String(),
          'schemaVersion': 1,
        },
      }),
    );

    expect(cache().sizeOf('/stale'), isNull);
  });

  test('entries written under a different schema are rejected', () {
    store().parent.createSync(recursive: true);
    store().writeAsStringSync(
      jsonEncode({
        '/old': {
          'size': 999,
          'updated': DateTime.now().toIso8601String(),
          'schemaVersion': 99,
        },
      }),
    );

    expect(cache().sizeOf('/old'), isNull);
  });

  test('a corrupt store reads as empty instead of throwing', () {
    store().parent.createSync(recursive: true);
    store().writeAsStringSync('{ not json');

    expect(cache().sizeOf('/anything'), isNull);
  });

  test('a zero or unknown size is never stored', () {
    final subject = cache()
      ..store('/zero', 0)
      ..store('/unknown', null);

    expect(subject.sizeOf('/zero'), isNull);
    expect(subject.sizeOf('/unknown'), isNull);
    // Nothing worth recording means no file was written at all.
    expect(store().existsSync(), isFalse);
  });

  test('re-storing the same size does not rewrite the store', () async {
    final subject = cache()..store('/steady', 1024);
    final firstWrite = store().lastModifiedSync();

    await Future<void>.delayed(const Duration(milliseconds: 20));
    subject.store('/steady', 1024);

    expect(store().lastModifiedSync(), firstWrite);
  });

  test('a changed size does rewrite the store', () {
    final subject = cache()..store('/growing', 1024);
    subject.store('/growing', 2048);

    expect(cache().sizeOf('/growing'), 2048);
  });

  test('caching is disabled when there is no cache directory', () {
    final subject = OverviewCache(cacheDirectory: null)..store('/x', 10);

    expect(subject.sizeOf('/x'), isNull);
  });
}
