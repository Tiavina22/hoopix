import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/optimize/data/datasources/optimize_task_runner.dart';
import 'package:hoopix/features/optimize/data/repositories/optimize_repository_impl.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';

class _FakeTask implements OptimizeTaskRunner {
  _FakeTask(this.task, this.outcome, {this.detail});

  @override
  final OptimizeTask task;
  final OptimizeOutcome outcome;
  final String? detail;

  @override
  Future<OptimizeTaskResult> run() async =>
      OptimizeTaskResult(task: task, outcome: outcome, detail: detail);
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
    final home = await Directory.systemTemp.createTemp('hoopix_optimize_');
    addTearDown(() => home.deleteSync(recursive: true));
    final repository = OptimizeRepositoryImpl(
      home: home.path,
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

  group('operation log', () {
    late Directory home;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('hoopix_optimize_log_');
    });

    tearDown(() async {
      if (home.existsSync()) await home.delete(recursive: true);
    });

    List<Map<String, Object?>> readLog() {
      final file = File('${home.path}/Library/Logs/hoopix/operations.log');
      if (!file.existsSync()) return const [];
      return [
        for (final line in file.readAsLinesSync())
          if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
      ];
    }

    const task = OptimizeTask(
      action: 'launch_agents_cleanup',
      name: 'Launch Agents Cleanup',
      description: 'd',
    );

    Future<List<Map<String, Object?>>> logFor(
      OptimizeOutcome outcome, {
      String? detail,
    }) async {
      await OptimizeRepositoryImpl(
        home: home.path,
        tasks: [_FakeTask(task, outcome, detail: detail)],
      ).runAll().toList();
      return readLog();
    }

    test('a task that changed something is recorded as applied', () async {
      final entries = await logFor(OptimizeOutcome.applied);

      expect(entries, hasLength(1));
      expect(entries.single['command'], 'optimize');
      expect(entries.single['outcome'], 'applied');
      // A task has no path, so its readable name is what History shows.
      expect(entries.single['path'], 'Launch Agents Cleanup');
    });

    test(
      'a task that failed is recorded as refused, with its reason',
      () async {
        final entries = await logFor(
          OptimizeOutcome.failed,
          detail: 'launchctl did not answer',
        );

        expect(entries.single['outcome'], 'refused');
        expect(entries.single['detail'], 'launchctl did not answer');
      },
    );

    test('a task held back on purpose is recorded as skipped', () async {
      final entries = await logFor(
        OptimizeOutcome.skipped,
        detail: 'no administrator access',
      );

      expect(entries.single['outcome'], 'skipped');
      expect(entries.single['detail'], 'no administrator access');
    });

    test('a task that did nothing leaves no record at all', () async {
      for (final outcome in [
        OptimizeOutcome.unchanged,
        OptimizeOutcome.unavailable,
        OptimizeOutcome.attention,
      ]) {
        expect(await logFor(outcome), isEmpty, reason: outcome.name);
      }
    });

    test('one record per task that acted, in the order they ran', () async {
      const other = OptimizeTask(action: 'b', name: 'B', description: 'd');
      await OptimizeRepositoryImpl(
        home: home.path,
        tasks: [
          _FakeTask(task, OptimizeOutcome.applied),
          _FakeTask(other, OptimizeOutcome.unchanged),
          _FakeTask(other, OptimizeOutcome.failed),
        ],
      ).runAll().toList();

      expect(readLog().map((e) => e['outcome']), ['applied', 'refused']);
    });

    test('recording never changes what runAll reports', () async {
      final results = await OptimizeRepositoryImpl(
        home: home.path,
        tasks: [_FakeTask(task, OptimizeOutcome.failed, detail: 'x')],
      ).runAll().toList();

      expect(results.single.outcome, OptimizeOutcome.failed);
      expect(results.single.detail, 'x');
    });
  });
}
