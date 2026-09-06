import 'package:hoopix/features/optimize/data/datasources/cache_refresh_task.dart';
import 'package:hoopix/features/optimize/data/datasources/coreduet_cleanup_task.dart';
import 'package:hoopix/features/optimize/data/datasources/disk_permissions_repair_task.dart';
import 'package:hoopix/features/optimize/data/datasources/dns_flush_tracker.dart';
import 'package:hoopix/features/optimize/data/datasources/fix_broken_configs_task.dart';
import 'package:hoopix/features/optimize/data/datasources/launch_agents_cleanup_task.dart';
import 'package:hoopix/features/optimize/data/datasources/launch_services_rebuild_task.dart';
import 'package:hoopix/features/optimize/data/datasources/legacy_overrides_audit_task.dart';
import 'package:hoopix/features/optimize/data/datasources/network_optimization_task.dart';
import 'package:hoopix/features/optimize/data/datasources/network_stack_optimize_task.dart';
import 'package:hoopix/features/optimize/data/datasources/notification_cleanup_task.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/periodic_maintenance_task.dart';
import 'package:hoopix/features/optimize/data/datasources/prevent_network_dsstore_task.dart';
import 'package:hoopix/features/optimize/data/datasources/quarantine_cleanup_task.dart';
import 'package:hoopix/features/optimize/data/datasources/saved_state_cleanup_task.dart';
import 'package:hoopix/features/optimize/data/datasources/shared_file_list_repair_task.dart';
import 'package:hoopix/features/optimize/data/datasources/spotlight_index_optimize_task.dart';
import 'package:hoopix/features/optimize/data/datasources/spotlight_orphan_rules_cleanup_task.dart';
import 'package:hoopix/features/optimize/data/datasources/sqlite_vacuum_task.dart';
import 'package:hoopix/features/optimize/data/datasources/system_maintenance_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';
import 'package:hoopix/features/optimize/domain/repositories/optimize_repository.dart';

/// Runs a fixed, ordered list of maintenance tasks — the complete port of
/// Mole's optimize catalog (`lib/optimize/catalog.sh`), except two
/// deliberate exclusions. `disk_verify` is never ported: Mole itself ships
/// it off by default, behind an undocumented env var, because `diskutil
/// verifyVolume` can freeze the system on an APFS-inconsistent volume — the
/// risk outweighs the value here too. `login_items_audit` needs
/// Automation/Apple Events permission for `System Events`, a TCC-gated
/// capability this app does not request; it stays out until that's
/// deliberately added.
///
/// The sudo-gated tasks each request administrator privileges through
/// [PrivilegedCommand] independently, rather than one upfront session the
/// way Mole's CLI establishes with `ensure_sudo_session` — see that
/// channel's own docs for why a maintenance run touching several of them
/// still usually prompts only once in practice. [DnsFlushTracker] is
/// constructed once here and shared between [SystemMaintenanceTask] and
/// [NetworkOptimizationTask] so the two never flush DNS twice in one run,
/// mirroring Mole's own `MOLE_DNS_FLUSHED` dedup — [SystemMaintenanceTask]
/// must stay ordered before [NetworkOptimizationTask] for that to hold,
/// the same order Mole's own catalog registers them in.
class OptimizeRepositoryImpl implements OptimizeRepository {
  OptimizeRepositoryImpl({
    required String home,
    List<OptimizeTaskRunner>? tasks,
  }) : _tasks = tasks ?? _defaultTasks(home);

  static List<OptimizeTaskRunner> _defaultTasks(String home) {
    final dnsFlushTracker = DnsFlushTracker();
    return [
      PreventNetworkDsStoreTask(),
      LegacyOverridesAuditTask(),
      CacheRefreshTask(home: home),
      SavedStateCleanupTask(home: home),
      QuarantineCleanupTask(home: home),
      NotificationCleanupTask(home: home),
      CoreduetCleanupTask(home: home),
      SharedFileListRepairTask(home: home),
      FixBrokenConfigsTask(home: home),
      SpotlightOrphanRulesCleanupTask(home: home),
      LaunchServicesRebuildTask(),
      LaunchAgentsCleanupTask(home: home),
      SqliteVacuumTask(home: home),
      SystemMaintenanceTask(dnsFlushTracker: dnsFlushTracker),
      NetworkOptimizationTask(dnsFlushTracker: dnsFlushTracker),
      NetworkStackOptimizeTask(),
      DiskPermissionsRepairTask(home: home),
      SpotlightIndexOptimizeTask(),
      PeriodicMaintenanceTask(),
    ];
  }

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
