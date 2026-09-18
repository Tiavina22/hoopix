import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/features/history/domain/entities/day_group.dart';
import 'package:hoopix/features/history/domain/entities/operation_history_entry.dart';

OperationHistoryEntry _entry(DateTime at, String path) => OperationHistoryEntry(
  at: at,
  command: 'uninstall',
  outcome: OperationOutcome.trashed,
  path: path,
);

void main() {
  test('groups consecutive entries on the same calendar day', () {
    final groups = groupHistoryByDay([
      _entry(DateTime(2026, 1, 2, 23, 59), '/late'),
      _entry(DateTime(2026, 1, 2, 8), '/morning'),
      _entry(DateTime(2026, 1, 1, 12), '/yesterday'),
    ]);

    expect(groups, hasLength(2));
    expect(groups[0].day, DateTime(2026, 1, 2));
    expect(groups[0].entries.map((e) => e.path), ['/late', '/morning']);
    expect(groups[1].day, DateTime(2026, 1, 1));
    expect(groups[1].entries.map((e) => e.path), ['/yesterday']);
  });

  test('never merges across a boundary even if the day repeats later', () {
    final groups = groupHistoryByDay([
      _entry(DateTime(2026, 1, 2), '/a'),
      _entry(DateTime(2026, 1, 1), '/b'),
      _entry(DateTime(2026, 1, 2), '/c'),
    ]);

    expect(groups.map((g) => g.day), [
      DateTime(2026, 1, 2),
      DateTime(2026, 1, 1),
      DateTime(2026, 1, 2),
    ]);
  });

  test('an empty list has no groups', () {
    expect(groupHistoryByDay(const []), isEmpty);
  });

  test('a single entry is its own single-item group', () {
    final groups = groupHistoryByDay([_entry(DateTime(2026, 1, 1), '/only')]);

    expect(groups, hasLength(1));
    expect(groups.single.entries, hasLength(1));
  });
}
