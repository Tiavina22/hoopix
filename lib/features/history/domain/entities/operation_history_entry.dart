import 'package:hoopix/core/platform/operation_log.dart';

/// One past decision hoopix made and recorded, for review only — nothing
/// here can be retried, undone, or acted on from this screen.
class OperationHistoryEntry {
  const OperationHistoryEntry({
    required this.at,
    required this.command,
    required this.outcome,
    required this.path,
    this.detail,
    this.sizeBytes,
  });

  final DateTime at;

  /// The feature that made the decision — `'clean'`, `'uninstall'`, and
  /// whatever else calls [OperationLog.record] in the future. Kept as the
  /// raw string a command wrote rather than a closed enum, so a new
  /// command's history shows up without this entity needing a release.
  final String command;

  final OperationOutcome outcome;
  final String path;

  /// Why, when [outcome] alone doesn't say — a refusal's reason, a brew
  /// command that ran, and so on. This is the field the CapCut confusion
  /// showed was missing from the app entirely: the log always had it, nothing
  /// showed it.
  final String? detail;

  final int? sizeBytes;
}
