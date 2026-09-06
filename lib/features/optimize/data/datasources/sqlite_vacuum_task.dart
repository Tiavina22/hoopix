import 'dart:io';

import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/domain/entities/path_protection.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_sqlite_vacuum` (`lib/optimize/tasks.sh`): compacts Mail,
/// Safari, and Messages' own SQLite databases by reclaiming free pages —
/// `VACUUM` never deletes rows, only the emptied space `DELETE`/normal
/// use already left behind. Every safety check Mole runs stays: none of
/// the three apps may be running (a live app can still be writing to the
/// file underneath the check), each candidate must pass
/// `PRAGMA integrity_check` before `VACUUM` touches it, and anything over
/// 100MB or already under a 5% free-page ratio is left alone rather than
/// spending the time.
///
/// `file -b` confirming the candidate is actually a SQLite database (not a
/// `.plist` or empty placeholder that happens to sit at one of these
/// fixed paths) runs before any of the above, the same order Mole checks
/// it in.
///
/// The Mail target is inert in practice: every `Envelope Index*` candidate
/// lives under `~/Library/Mail/...`, which [shouldProtectPath] blocks via
/// its own `*/Library/Mail/*` rule (`app_protection.sh`), and Mole's own
/// `opt_sqlite_vacuum` runs the identical `should_protect_path "$db_file"
/// && continue` guard before touching any candidate — so Mole itself only
/// ever compacts Safari and Messages' databases too. The discovery and
/// vacuum logic for Mail stays, faithful to Mole's source, rather than
/// dropped — the same shape as `CacheRefreshTask` and
/// `QuarantineCleanupTask`'s own documented quirks.
class SqliteVacuumTask implements OptimizeTaskRunner {
  SqliteVacuumTask({
    required this.home,
    ProcessRunner? probe,
    Directory Function(String path)? directory,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 20)),
       _directory = directory ?? Directory.new;

  final String home;
  final ProcessRunner _probe;
  final Directory Function(String path) _directory;

  static const _busyApps = ['Mail', 'Safari', 'Messages'];
  static const _maxSizeBytes = 100 * 1024 * 1024;
  // freelist_count * 100 < page_count * 5, i.e. under 5% free pages.
  static const _optimalFreelistNumerator = 100;
  static const _optimalFreelistDenominator = 5;

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'sqlite_vacuum',
    name: 'Database Optimization',
    description:
        'Compress SQLite databases for Mail, Safari & Messages (skips if '
        'apps are running)',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    for (final app in _busyApps) {
      final result = await _probe.run('pgrep', ['-x', app]);
      if (result.isSuccess) {
        return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.skipped);
      }
      final failure = result.failure;
      if (failure?.kind == ProcessFailureKind.notFound) {
        return OptimizeTaskResult(
          task: task,
          outcome: OptimizeOutcome.unavailable,
        );
      }
      final confirmedNotRunning =
          failure?.kind == ProcessFailureKind.nonZeroExit &&
          failure?.exitCode == 1;
      if (!confirmedNotRunning) {
        return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.failed);
      }
    }

    final sqliteAvailable = await _probe.run('sqlite3', ['-version']);
    if (!sqliteAvailable.isSuccess) {
      return OptimizeTaskResult(
        task: task,
        outcome: OptimizeOutcome.unavailable,
      );
    }

    var vacuumed = 0;
    var timedOut = 0;
    var failed = 0;
    var policySkipped = 0;

    for (final path in _candidatePaths()) {
      final outcome = await _process(path);
      switch (outcome) {
        case _CandidateOutcome.vacuumed:
          vacuumed++;
        case _CandidateOutcome.timedOut:
          timedOut++;
        case _CandidateOutcome.failed:
          failed++;
        case _CandidateOutcome.policySkipped:
          policySkipped++;
        case _CandidateOutcome.skipped:
          break;
      }
    }

    return OptimizeTaskResult(
      task: task,
      outcome: optimizeOutcomeFromCounts(
        applied: vacuumed,
        failed: timedOut + failed,
        skipped: policySkipped,
      ),
    );
  }

  Future<_CandidateOutcome> _process(String path) async {
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return _CandidateOutcome.skipped;
    }
    if (path.endsWith('-wal') || path.endsWith('-shm')) {
      return _CandidateOutcome.skipped;
    }
    if (shouldProtectPath(path, home: home)) return _CandidateOutcome.skipped;

    final typeCheck = await _probe.run('file', ['-b', path]);
    if (!(typeCheck.stdout ?? '').contains('SQLite')) {
      return _CandidateOutcome.skipped;
    }

    final int size;
    try {
      size = File(path).statSync().size;
    } on FileSystemException {
      return _CandidateOutcome.skipped;
    }
    if (size > _maxSizeBytes) return _CandidateOutcome.policySkipped;

    final pageInfo = await _probe.run('sqlite3', [
      path,
      'PRAGMA page_count; PRAGMA freelist_count;',
    ]);
    if (!pageInfo.isSuccess) return _CandidateOutcome.failed;
    final lines = (pageInfo.stdout ?? '').trim().split('\n');
    final pageCount = lines.isNotEmpty ? int.tryParse(lines[0].trim()) : null;
    final freelistCount = lines.length > 1
        ? int.tryParse(lines[1].trim())
        : null;
    if (pageCount != null &&
        freelistCount != null &&
        pageCount > 0 &&
        freelistCount * _optimalFreelistNumerator <
            pageCount * _optimalFreelistDenominator) {
      return _CandidateOutcome.skipped; // already compact
    }

    final integrity = await _probe.run('sqlite3', [
      path,
      'PRAGMA integrity_check;',
    ]);
    if (!integrity.isSuccess || integrity.stdout?.trim() != 'ok') {
      return _CandidateOutcome.failed;
    }

    final vacuum = await _probe.run('sqlite3', [path, 'VACUUM;']);
    if (vacuum.isSuccess) return _CandidateOutcome.vacuumed;
    if (vacuum.failure?.kind == ProcessFailureKind.timedOut) {
      return _CandidateOutcome.timedOut;
    }
    return _CandidateOutcome.failed;
  }

  /// Every fixed database path Mole targets, plus every `V*` Mail account
  /// directory's own `Envelope Index` file(s) — including the `-wal`/`-shm`
  /// siblings a plain filename match picks up, filtered back out in
  /// [_process] the same way Mole's own glob-then-exclude does.
  List<String> _candidatePaths() {
    final paths = <String>[
      '$home/Library/Messages/chat.db',
      '$home/Library/Safari/History.db',
      '$home/Library/Safari/TopSites.db',
    ];

    final mailRoot = '$home/Library/Mail';
    for (final accountDir in _entriesStartingWith(mailRoot, 'V')) {
      final mailDataDir = '$accountDir/MailData';
      paths.addAll(_entriesStartingWith(mailDataDir, 'Envelope Index'));
    }

    return paths;
  }

  List<String> _entriesStartingWith(String dir, String prefix) {
    try {
      return [
        for (final entity in _directory(dir).listSync(followLinks: false))
          if (entity.path.split('/').last.startsWith(prefix)) entity.path,
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }
}

enum _CandidateOutcome { vacuumed, timedOut, failed, policySkipped, skipped }
