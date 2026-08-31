import 'dart:convert';
import 'dart:io';

/// What happened to one path during a run.
enum OperationOutcome { trashed, refused, skipped }

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
        '${jsonEncode({
          'at': DateTime.now().toIso8601String(),
          'command': command,
          'outcome': outcome.name,
          'path': targetPath,
          'detail': ?detail,
          'sizeBytes': ?sizeBytes,
        })}\n',
        mode: FileMode.append,
      );
    } on Object {
      // An unwritable log is a diagnostics problem, not a reason to abandon
      // work the user asked for.
    }
  }
}
