import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';

const _entries = [
  AnalyzeEntry(path: '/a', name: 'a', isDirectory: true, sizeBytes: 10),
  AnalyzeEntry(path: '/b', name: 'b', isDirectory: true, sizeBytes: 20),
];

void main() {
  test('totalEntryCount falls back to the entries shown when not given', () {
    const scan = DirectoryScan(
      path: '/root',
      status: DirectoryScanStatus.loaded,
      entries: _entries,
    );

    expect(scan.totalEntryCount, 2);
  });

  test('an explicit totalEntryCount can exceed the capped list', () {
    const scan = DirectoryScan(
      path: '/root',
      status: DirectoryScanStatus.loaded,
      entries: _entries,
      totalEntryCount: 340,
    );

    expect(scan.totalEntryCount, 340);
    expect(scan.entries, hasLength(2));
  });
}
