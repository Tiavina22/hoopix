import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/data/repositories/optimize_repository_impl.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

class _FakeTask implements OptimizeTaskRunner {
  _FakeTask(this.task, this.outcome);

  @override
  final OptimizeTask task;
  final OptimizeOutcome outcome;

  @override
  Future<OptimizeTaskResult> run() async =>
      OptimizeTaskResult(task: task, outcome: outcome);
}

const _taskA = OptimizeTask(action: 'a', name: 'A', description: 'first');
const _taskB = OptimizeTask(action: 'b', name: 'B', description: 'second');

void main() {
  test('catalog reflects the injected tasks, in order', () {
    final repository = OptimizeRepositoryImpl(
      home: '/tmp',
      tasks: [
        _FakeTask(_taskA, OptimizeOutcome.applied),
        _FakeTask(_taskB, OptimizeOutcome.unchanged),
      ],
    );

    expect(repository.catalog, [_taskA, _taskB]);
  });

  test('runAll emits one result per task, in order', () async {
    final repository = OptimizeRepositoryImpl(
      home: '/tmp',
      tasks: [
        _FakeTask(_taskA, OptimizeOutcome.applied),
        _FakeTask(_taskB, OptimizeOutcome.failed),
      ],
    );

    final results = await repository.runAll().toList();

    expect(results.map((r) => r.task.action), ['a', 'b']);
    expect(results.map((r) => r.outcome), [
      OptimizeOutcome.applied,
      OptimizeOutcome.failed,
    ]);
  });

  test('default construction wires the full catalog, in order', () {
    final repository = OptimizeRepositoryImpl(home: '/tmp');

    expect(repository.catalog.map((t) => t.action), [
      'prevent_network_dsstore',
      'legacy_overrides_audit',
      'cache_refresh',
      'saved_state_cleanup',
      'quarantine_cleanup',
      'notification_cleanup',
      'coreduet_cleanup',
      'shared_file_list_repair',
      'fix_broken_configs',
      'spotlight_orphan_rules_cleanup',
      'launch_services_rebuild',
      'launch_agents_cleanup',
      'sqlite_vacuum',
      // system_maintenance must precede network_optimization: they share
      // one DnsFlushTracker, and only that order dedups the DNS flush.
      'system_maintenance',
      'network_optimization',
      'network_stack_optimize',
      'disk_permissions_repair',
      'spotlight_index_optimize',
      'periodic_maintenance',
    ]);
  });
}
