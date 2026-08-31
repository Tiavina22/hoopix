import 'dart:convert';

import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';
import 'package:hoopix/features/analyze/domain/entities/entry_hint.dart';

/// The overview rows Mole's JSON export marks `insight: true` — the "hidden
/// space" rows, as opposed to the four structural roots (Home, User
/// Library, Applications, System Library).
const _insightKinds = {
  OverviewRowKind.iosBackups,
  OverviewRowKind.oldDownloads,
  OverviewRowKind.tool,
};

/// Serializes what is currently on screen, matching the field names and
/// shape of Mole's `--json` mode (`jsonOutput`/`jsonEntry` in `json.go`) —
/// though not quite its scope: Mole's `--json` re-scans a directory in full,
/// uncapped, since a one-shot CLI process has no "current view" to draw
/// from. This exports the listing already on screen instead — the same 30
/// biggest entries the person is looking at, with [DirectoryScan.totalBytes]
/// and [DirectoryScan.totalEntryCount] still the true, uncapped totals.
String buildAnalyzeJson(
  DirectoryScan scan, {
  required bool isOverview,
  List<AnalyzeEntry>? largeFiles,
}) {
  final json = <String, Object?>{
    'path': scan.path,
    'overview': isOverview,
    'entries': [for (final entry in scan.entries) _entryJson(entry, isOverview)],
    if (largeFiles != null && largeFiles.isNotEmpty)
      'large_files': [
        for (final file in largeFiles)
          {
            'name': file.name,
            'path': file.path,
            'size': file.sizeBytes ?? 0,
          },
      ],
    'total_size': scan.totalBytes ?? 0,
    if (scan.totalEntryCount > 0) 'total_files': scan.totalEntryCount,
  };

  return const JsonEncoder.withIndent('  ').convert(json);
}

Map<String, Object?> _entryJson(AnalyzeEntry entry, bool isOverview) {
  final cleanable = isCleanableDirectory(entry);
  final accessed = entry.accessed;
  return {
    'name': entry.name,
    'path': entry.path,
    'size': entry.sizeBytes ?? 0,
    'is_dir': entry.isDirectory,
    if (isOverview && _insightKinds.contains(entry.overviewKind)) 'insight': true,
    if (cleanable) 'cleanable': true,
    if (accessed != null) 'last_access': accessed.toIso8601String(),
  };
}
