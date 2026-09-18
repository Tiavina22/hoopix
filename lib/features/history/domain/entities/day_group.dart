import 'package:hoopix/features/history/domain/entities/operation_history_entry.dart';

/// Every entry recorded on the same calendar day, in [entries]' own order.
class DayGroup {
  const DayGroup({required this.day, required this.entries});

  /// Midnight of the day these entries fall on, in local time.
  final DateTime day;
  final List<OperationHistoryEntry> entries;
}

/// Splits [entries] into consecutive runs that share a calendar day (local
/// time), keeping [entries]' own order both across and within groups — the
/// repository already returns newest first, so this does too. Never
/// reorders across a boundary: if the log somehow interleaves two days,
/// each run is its own group rather than being merged.
List<DayGroup> groupHistoryByDay(List<OperationHistoryEntry> entries) {
  final groups = <DayGroup>[];
  DateTime? currentDay;
  List<OperationHistoryEntry>? currentEntries;

  for (final entry in entries) {
    final day = DateTime(entry.at.year, entry.at.month, entry.at.day);
    if (day != currentDay) {
      currentDay = day;
      currentEntries = [];
      groups.add(DayGroup(day: day, entries: currentEntries));
    }
    currentEntries!.add(entry);
  }

  return groups;
}
