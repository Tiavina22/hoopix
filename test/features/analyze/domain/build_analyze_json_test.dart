import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';
import 'package:hoopix/features/analyze/domain/usecases/build_analyze_json.dart';

void main() {
  test('matches Mole\'s field names for a plain directory entry', () {
    const scan = DirectoryScan(
      path: '/Users/tester/Documents',
      status: DirectoryScanStatus.loaded,
      entries: [
        AnalyzeEntry(
          path: '/Users/tester/Documents/photos',
          name: 'photos',
          isDirectory: true,
          sizeBytes: 2048,
        ),
      ],
      totalBytes: 2048,
    );

    final json = jsonDecode(buildAnalyzeJson(scan, isOverview: false));

    expect(json['path'], '/Users/tester/Documents');
    expect(json['overview'], isFalse);
    expect(json['entries'], [
      {
        'name': 'photos',
        'path': '/Users/tester/Documents/photos',
        'size': 2048,
        'is_dir': true,
      },
    ]);
    expect(json['total_size'], 2048);
  });

  test('cleanable and last_access are only present when they apply', () {
    final accessed = DateTime(2026, 1, 1);
    final scan = DirectoryScan(
      path: '/p',
      status: DirectoryScanStatus.loaded,
      entries: [
        AnalyzeEntry(
          path: '/p/node_modules',
          name: 'node_modules',
          isDirectory: true,
          sizeBytes: 4096,
          accessed: accessed,
        ),
      ],
      totalBytes: 4096,
    );

    final entry =
        (jsonDecode(buildAnalyzeJson(scan, isOverview: false))['entries']
                as List)
            .single
        as Map<String, Object?>;

    expect(entry['cleanable'], isTrue);
    expect(entry['last_access'], accessed.toIso8601String());
  });

  test('an ordinary file omits cleanable and last_access entirely', () {
    const scan = DirectoryScan(
      path: '/p',
      status: DirectoryScanStatus.loaded,
      entries: [
        AnalyzeEntry(path: '/p/note.txt', name: 'note.txt', isDirectory: false),
      ],
    );

    final entry =
        (jsonDecode(buildAnalyzeJson(scan, isOverview: false))['entries']
                as List)
            .single
        as Map<String, Object?>;

    expect(entry.containsKey('cleanable'), isFalse);
    expect(entry.containsKey('last_access'), isFalse);
  });

  test('insight is set only for hidden-space overview rows', () {
    const scan = DirectoryScan(
      path: overviewPath,
      status: DirectoryScanStatus.loaded,
      entries: [
        AnalyzeEntry(
          path: '/Users/tester',
          name: 'Home',
          isDirectory: true,
          overviewKind: OverviewRowKind.home,
        ),
        AnalyzeEntry(
          path: '/Users/tester/Downloads',
          name: 'Old Downloads',
          isDirectory: true,
          overviewKind: OverviewRowKind.oldDownloads,
        ),
      ],
    );

    final entries = jsonDecode(buildAnalyzeJson(scan, isOverview: true))['entries'] as List;

    expect((entries[0] as Map).containsKey('insight'), isFalse);
    expect((entries[1] as Map)['insight'], isTrue);
  });

  test('the same overview row is never marked insight outside the overview', () {
    const scan = DirectoryScan(
      path: '/Users/tester',
      status: DirectoryScanStatus.loaded,
      entries: [
        AnalyzeEntry(
          path: '/Users/tester/Downloads',
          name: 'Downloads',
          isDirectory: true,
          overviewKind: OverviewRowKind.oldDownloads,
        ),
      ],
    );

    final entry =
        (jsonDecode(buildAnalyzeJson(scan, isOverview: false))['entries']
                as List)
            .single
        as Map<String, Object?>;

    expect(entry.containsKey('insight'), isFalse);
  });

  test('large files are included alongside entries when present', () {
    const scan = DirectoryScan(path: '/p', status: DirectoryScanStatus.loaded);
    const largeFiles = [
      AnalyzeEntry(
        path: '/p/movie.mov',
        name: 'movie.mov',
        isDirectory: false,
        sizeBytes: 900,
      ),
    ];

    final json = jsonDecode(
      buildAnalyzeJson(scan, isOverview: false, largeFiles: largeFiles),
    );

    expect(json['large_files'], [
      {'name': 'movie.mov', 'path': '/p/movie.mov', 'size': 900},
    ]);
  });

  test('an empty large-files list is omitted, not sent as []', () {
    const scan = DirectoryScan(path: '/p', status: DirectoryScanStatus.loaded);

    final json = jsonDecode(
      buildAnalyzeJson(scan, isOverview: false, largeFiles: const []),
    );

    expect(json.containsKey('large_files'), isFalse);
  });

  test('a directory with more children than are shown reports the true count', () {
    const scan = DirectoryScan(
      path: '/p',
      status: DirectoryScanStatus.loaded,
      entries: [
        AnalyzeEntry(path: '/p/a', name: 'a', isDirectory: true, sizeBytes: 1),
      ],
      totalBytes: 500,
      totalEntryCount: 340,
    );

    final json = jsonDecode(buildAnalyzeJson(scan, isOverview: false));

    expect(json['total_files'], 340);
    expect((json['entries'] as List), hasLength(1));
  });
}
