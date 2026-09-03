import 'package:hoopix/features/optimize/data/datasources/cache_refresh_task.dart';
import 'package:hoopix/features/optimize/data/datasources/coreduet_cleanup_task.dart';
import 'package:hoopix/features/optimize/data/datasources/fix_broken_configs_task.dart';
import 'package:hoopix/features/optimize/data/datasources/legacy_overrides_audit_task.dart';
import 'package:hoopix/features/optimize/data/datasources/notification_cleanup_task.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/prevent_network_dsstore_task.dart';
import 'package:hoopix/features/optimize/data/datasources/quarantine_cleanup_task.dart';
import 'package:hoopix/features/optimize/data/datasources/saved_state_cleanup_task.dart';
import 'package:hoopix/features/optimize/data/datasources/shared_file_list_repair_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';
import 'package:hoopix/features/optimize/domain/repositories/optimize_repository.dart';

/// Runs a fixed, ordered list of maintenance tasks — the no-admin-access
/// slice of Mole's optimize catalog (`lib/optimize/catalog.sh`) ported so
/// far. Every task here needs no `sudo` and touches only regenerable,
/// user-owned state; the catalog's sudo-gated tasks (DNS/route flushing,
/// permission repair, Spotlight reindex, `periodic`) need their own
/// administrator-privileges channel and are not wired in yet. `disk_verify`
/// is deliberately never ported: Mole itself ships it off by default,
/// behind an undocumented env var, because `diskutil verifyVolume` can
/// freeze the system on an APFS-inconsistent volume — the risk outweighs
/// the value here too. `login_items_audit` needs Automation/Apple Events
/// permission for `System Events`, a TCC-gated capability this app does not
/// request; it stays out until that's deliberately added.
class OptimizeRepositoryImpl implements OptimizeRepository {
  OptimizeRepositoryImpl({
    required String home,
    List<OptimizeTaskRunner>? tasks,
  }) : _tasks =
           tasks ??
           [
             PreventNetworkDsStoreTask(),
             LegacyOverridesAuditTask(),
             CacheRefreshTask(home: home),
             SavedStateCleanupTask(home: home),
             QuarantineCleanupTask(home: home),
             NotificationCleanupTask(home: home),
             CoreduetCleanupTask(home: home),
             SharedFileListRepairTask(home: home),
             FixBrokenConfigsTask(home: home),
           ];

  final List<OptimizeTaskRunner> _tasks;

  @override
  List<OptimizeTask> get catalog => [for (final t in _tasks) t.task];

  @override
  Stream<OptimizeTaskResult> runAll() async* {
    for (final t in _tasks) {
      yield await t.run();
    }
  }
}
