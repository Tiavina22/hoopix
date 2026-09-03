import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

/// Ports `opt_prune_spotlight_orphan_rules` (`lib/optimize/tasks.sh`):
/// Spotlight keeps a per-app "search this app's content" preference —
/// `EnabledPreferenceRules` — that never loses an entry on its own when the
/// app is removed. This drops entries for apps [BundleInstallResolver]
/// confirms are genuinely gone, keeping everything else: `System.*` and
/// `com.apple.*` rules outright (never touched, even though some pass the
/// reverse-DNS shape check — they are not removable app bundles), anything
/// not shaped like a bundle id, and any bundle id the resolver could not
/// rule out.
///
/// Rewritten through `defaults write` (or `defaults delete` when nothing
/// survives), never by editing plist array indices directly — the same
/// reason Mole's own comment gives: a direct file edit can be overwritten
/// by `cfprefsd`'s own cache, and going through `defaults` is what makes
/// System Settings see the change and keep it.
class SpotlightOrphanRulesCleanupTask implements OptimizeTaskRunner {
  SpotlightOrphanRulesCleanupTask({
    required this.home,
    ProcessRunner? probe,
    BundleInstallResolver? resolver,
  }) : _probe = probe ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _resolver = resolver ?? BundleInstallResolver(home: home, probe: probe);

  final String home;
  final ProcessRunner _probe;
  final BundleInstallResolver _resolver;

  static const _domain = 'com.apple.spotlight';
  static const _key = 'EnabledPreferenceRules';

  @override
  OptimizeTask get task => const OptimizeTask(
    action: 'spotlight_orphan_rules_cleanup',
    name: 'Spotlight Orphan Rules',
    description:
        'Remove Spotlight search-rule entries for apps that are no longer '
        'installed',
  );

  @override
  Future<OptimizeTaskResult> run() async {
    final plist = '$home/Library/Preferences/$_domain.plist';

    final present = await _probe.run('defaults', ['read', _domain, _key]);
    if (!present.isSuccess) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    final keep = <String>[];
    var removedCount = 0;
    var index = 0;
    while (true) {
      final entry = await _probe.run('/usr/libexec/PlistBuddy', [
        '-c',
        'Print :$_key:$index',
        plist,
      ]);
      if (!entry.isSuccess) break;
      final value = entry.stdout?.trim() ?? '';
      index++;

      if (value.startsWith('System.') || value.startsWith('com.apple.')) {
        keep.add(value);
        continue;
      }
      if (!isReverseDnsBundleId(value)) {
        keep.add(value);
        continue;
      }
      if (await _resolver.hasInstalledApp(value)) {
        keep.add(value);
      } else {
        removedCount++;
      }
    }

    if (removedCount == 0) {
      return OptimizeTaskResult(task: task, outcome: OptimizeOutcome.unchanged);
    }

    final write = keep.isEmpty
        ? await _probe.run('defaults', ['delete', _domain, _key])
        : await _probe.run('defaults', [
            'write',
            _domain,
            _key,
            '-array',
            ...keep,
          ]);

    return OptimizeTaskResult(
      task: task,
      outcome: write.isSuccess
          ? OptimizeOutcome.applied
          : OptimizeOutcome.failed,
    );
  }
}
