import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/optimize/data/datasources/periodic_maintenance_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_privileged_command.dart';

void main() {
  late Directory work;
  late String periodicPath;
  late String dailyLogPath;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('hoopix_periodic_');
    periodicPath = '${work.path}/periodic';
    dailyLogPath = '${work.path}/daily.out';
  });

  tearDown(() async {
    if (work.existsSync()) await work.delete(recursive: true);
  });

  PeriodicMaintenanceTask task({FakePrivilegedCommand? privileged}) =>
      PeriodicMaintenanceTask(
        privilegedCommand: privileged ?? FakePrivilegedCommand(const {}),
        periodicPath: periodicPath,
        dailyLogPath: dailyLogPath,
      );

  test('action id matches the catalog', () async {
    final result = await task().run();
    expect(result.task.action, 'periodic_maintenance');
  });

  test('unavailable when periodic itself is not installed', () async {
    final result = await task().run();
    expect(result.outcome, OptimizeOutcome.unavailable);
  });

  test('unchanged when the daily log is recent', () async {
    await File(periodicPath).create();
    final log = File(dailyLogPath);
    await log.create();
    await log.setLastModified(DateTime.now().subtract(const Duration(days: 1)));

    final result = await task().run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('runs maintenance when the daily log is 7+ days old', () async {
    await File(periodicPath).create();
    final log = File(dailyLogPath);
    await log.create();
    await log.setLastModified(
      DateTime.now().subtract(const Duration(days: 10)),
    );

    final privileged = FakePrivilegedCommand({
      'run_periodic_maintenance': null,
    });

    final result = await task(privileged: privileged).run();

    expect(result.outcome, OptimizeOutcome.applied);
    expect(privileged.calls, ['run_periodic_maintenance']);
  });

  test('a missing daily log is treated as stale, not healthy', () async {
    await File(periodicPath).create();

    final privileged = FakePrivilegedCommand({
      'run_periodic_maintenance': null,
    });

    final result = await task(privileged: privileged).run();

    expect(result.outcome, OptimizeOutcome.applied);
  });

  test('reports failed when elevation is declined', () async {
    await File(periodicPath).create();

    final result = await task(
      privileged: FakePrivilegedCommand({
        'run_periodic_maintenance': 'declined',
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });
}
