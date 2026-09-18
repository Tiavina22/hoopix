import 'dart:convert';
import 'dart:io';

/// What happened to one path during a run.
///
/// [cleared] is distinct from [trashed]: it means the path was reclaimed by
/// running its owning tool's own cache-clean command, or deleted outright,
/// rather than moved to the Trash, so — unlike [trashed] — it cannot be put
/// back.
///
/// [applied] is for a maintenance action that has no path to trash or clear:
/// it ran and changed something. [refused] also covers an action that was
/// attempted and did not complete, the same "did not go through" meaning it
/// already has for a refused Trash move.
enum OperationOutcome { trashed, refused, skipped, cleared, applied }

/// An append-only record of everything a destructive command did, and
/// everything it decided not to do.
///
/// Mole logs the same way, and for the same reason: a cleanup tool that
/// cannot be audited afterwards is one you have to take on faith. The log
/// lives at `~/Library/Logs/hoopix/operations.log`, which the path
/// protection rules refuse to delete — cleanup cannot remove its own record.
class OperationLog {
  const OperationLog({required this.home});

  final String home;

  String get path => '$home/Library/Logs/hoopix/operations.log';

  /// Records one decision. Best effort: failing to write a log line must
  /// never stop or fail the operation it is describing.
  void record({
    required String command,
    required OperationOutcome outcome,
    required String targetPath,
    String? detail,
    int? sizeBytes,
  }) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '${jsonEncode({'at': DateTime.now().toIso8601String(), 'command': command, 'outcome': outcome.name, 'path': targetPath, 'detail': ?detail, 'sizeBytes': ?sizeBytes})}\n',
        mode: FileMode.append,
      );
    } on Object {
      // An unwritable log is a diagnostics problem, not a reason to abandon
      // work the user asked for.
    }
  }
}
