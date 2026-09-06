/// Whether DNS has already been flushed once in the current run — shared
/// between [SystemMaintenanceTask] and [NetworkOptimizationTask] so that
/// running both in the same pass flushes DNS at most once, the same
/// dedup Mole's own `MOLE_DNS_FLUSHED` env var gives those two tasks
/// (`lib/optimize/tasks.sh`). `OptimizeRepositoryImpl` constructs one
/// instance and hands it to both.
class DnsFlushTracker {
  bool flushed = false;
}
