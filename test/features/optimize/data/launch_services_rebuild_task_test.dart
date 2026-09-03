import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/launch_services_rebuild_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  late Directory tempBin;
  late String lsregister;

  setUp(() async {
    tempBin = await Directory.systemTemp.createTemp('hoopix_lsregister_');
    lsregister = '${tempBin.path}/lsregister';
    await File(lsregister).create();
    await Process.run('chmod', ['+x', lsregister]);
  });

  tearDown(() async {
    if (tempBin.existsSync()) await tempBin.delete(recursive: true);
  });

  test('action id matches the catalog', () async {
    final result = await LaunchServicesRebuildTask(
      candidatePaths: const ['/nonexistent/lsregister'],
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.task.action, 'launch_services_rebuild');
  });

  test('unavailable when lsregister is not found at either path', () async {
    final result = await LaunchServicesRebuildTask(
      candidatePaths: const [
        '/nonexistent/one/lsregister',
        '/nonexistent/two/lsregister',
      ],
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.outcome, OptimizeOutcome.unavailable);
  });

  test('runs -gc then the full-domain rescan, and reports applied', () async {
    final result = await LaunchServicesRebuildTask(
      candidatePaths: [lsregister],
      probe: FakeProcessRunner({
        '$lsregister -gc': ProcessResult.success(''),
        '$lsregister -r -f -domain local -domain user -domain system':
            ProcessResult.success(''),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
  });

  test('retries without the system domain when the full rescan fails, and '
      'still reports applied on that success', () async {
    final result = await LaunchServicesRebuildTask(
      candidatePaths: [lsregister],
      probe: FakeProcessRunner({
        '$lsregister -gc': ProcessResult.success(''),
        '$lsregister -r -f -domain local -domain user -domain system':
            ProcessResult.failure(
              ProcessFailure.nonZeroExit('lsregister', 1, 'denied'),
            ),
        '$lsregister -r -f -domain local -domain user': ProcessResult.success(
          '',
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
  });

  test('reports failed when both rescan attempts fail', () async {
    final result = await LaunchServicesRebuildTask(
      candidatePaths: [lsregister],
      probe: FakeProcessRunner({
        '$lsregister -gc': ProcessResult.success(''),
        '$lsregister -r -f -domain local -domain user -domain system':
            ProcessResult.failure(
              ProcessFailure.nonZeroExit('lsregister', 1, 'denied'),
            ),
        '$lsregister -r -f -domain local -domain user': ProcessResult.failure(
          ProcessFailure.nonZeroExit('lsregister', 1, 'denied'),
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });

  test(
    'picks the second candidate path when the first is not executable',
    () async {
      final notExecutable = '${tempBin.path}/not-executable';
      await File(notExecutable).create();

      final result = await LaunchServicesRebuildTask(
        candidatePaths: [notExecutable, lsregister],
        probe: FakeProcessRunner({
          '$lsregister -gc': ProcessResult.success(''),
          '$lsregister -r -f -domain local -domain user -domain system':
              ProcessResult.success(''),
        }),
      ).run();

      expect(result.outcome, OptimizeOutcome.applied);
    },
  );
}
