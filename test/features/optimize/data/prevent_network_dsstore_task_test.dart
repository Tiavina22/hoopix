import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/prevent_network_dsstore_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _notSet() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('defaults', 1, ''));

void main() {
  test('action id matches the catalog', () async {
    final result = await PreventNetworkDsStoreTask(
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.task.action, 'prevent_network_dsstore');
  });

  test('writes both keys when neither is set, and reports applied', () async {
    final result = await PreventNetworkDsStoreTask(
      probe: FakeProcessRunner({
        'defaults read com.apple.desktopservices DSDontWriteNetworkStores':
            _notSet(),
        'defaults write com.apple.desktopservices DSDontWriteNetworkStores '
            '-bool true': ProcessResult.success(
          '',
        ),
        'defaults read com.apple.desktopservices DSDontWriteUSBStores':
            _notSet(),
        'defaults write com.apple.desktopservices DSDontWriteUSBStores '
            '-bool true': ProcessResult.success(
          '',
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
  });

  test('leaves an already-set key alone', () async {
    final result = await PreventNetworkDsStoreTask(
      probe: FakeProcessRunner({
        'defaults read com.apple.desktopservices DSDontWriteNetworkStores':
            ProcessResult.success('1\n'),
        'defaults read com.apple.desktopservices DSDontWriteUSBStores':
            ProcessResult.success('1\n'),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('reports failed when a write does not stick', () async {
    final result = await PreventNetworkDsStoreTask(
      probe: FakeProcessRunner({
        'defaults read com.apple.desktopservices DSDontWriteNetworkStores':
            _notSet(),
        'defaults write com.apple.desktopservices DSDontWriteNetworkStores '
            '-bool true': ProcessResult.failure(
          ProcessFailure.nonZeroExit('defaults', 1, 'denied'),
        ),
        'defaults read com.apple.desktopservices DSDontWriteUSBStores':
            ProcessResult.success('1\n'),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });
}
