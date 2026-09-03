import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

class _Override {
  const _Override(this.domain, this.key);
  final String domain;
  final String key;
}

/// Ports `opt_legacy_overrides_audit` (`lib/optimize/tasks.sh`): hidden App
/// Nap and disk-image verification overrides some old tweak tools used to
/// leave behind. Deletes only the override *key* — never the domain, never
/// a replacement value — which is exactly what restores macOS's own
/// default behavior; re-adding an override later is a normal `defaults
/// write` away, so this is not a destructive step against user data.
class LegacyOverridesAuditTask implements OptimizeTaskRunner {
  LegacyOverridesAuditTask({ProcessRunner? probe})
    : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5));

  final ProcessRunner _probe;

  static const _targets = [
    _Override('-g', 'NSAppSleepDisabled'),
    _Override('com.apple.frameworks.diskimages', 'skip-verify'),
    _Override('com.apple.frameworks.diskimages', 'skip-verify-locked'),
    _Override('com.apple.frameworks.diskimages', 'skip-verify-remote'),
  ];

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'legacy_overrides_audit',
    name: 'Legacy Overrides',
    description:
        'Remove hidden App Nap and disk-image verification overrides left '
        'by old tweak tools',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    var applied = 0;
    var failed = 0;

    for (final target in _targets) {
      final read = await _probe.run('defaults', [
        'read',
        target.domain,
        target.key,
      ]);
      if (!read.isSuccess) continue; // not overridden

      final value = read.stdout?.trim().toLowerCase();
      if (value != '1' && value != 'true' && value != 'yes') continue;

      final delete = await _probe.run('defaults', [
        'delete',
        target.domain,
        target.key,
      ]);
      if (delete.isSuccess) {
        applied++;
      } else {
        failed++;
      }
    }

    return OptimizeTaskResult(
      task: task,
      outcome: optimizeOutcomeFromCounts(applied: applied, failed: failed),
    );
  }
}
