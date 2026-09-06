import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/spotlight_index_optimize_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_privileged_command.dart';
import '../../../support/fake_process_runner.dart';

ProcessResult _acPower() =>
    ProcessResult.success('Now drawing from \'AC Power\'');
ProcessResult _battery() =>
    ProcessResult.success('Now drawing from \'Battery Power\'');
ProcessResult _fastFind() => ProcessResult.success('/Applications');

SpotlightIndexOptimizeTask task({
  required Map<String, ProcessResult> probeResponses,
  FakePrivilegedCommand? privileged,
}) => SpotlightIndexOptimizeTask(
  privilegedCommand: privileged ?? FakePrivilegedCommand(const {}),
  probe: FakeProcessRunner(probeResponses),
  betweenProbesDelay: Duration.zero,
);

void main() {
  test('action id matches the catalog', () async {
    final result = await task(
      probeResponses: {
        'mdutil -s /': ProcessResult.success('Indexing disabled.'),
      },
    ).run();

    expect(result.task.action, 'spotlight_index_optimize');
  });

  test('failed when the status probe itself cannot run', () async {
    final result = await task(
      probeResponses: {
        'mdutil -s /': ProcessResult.failure(
          ProcessFailure.nonZeroExit('mdutil', 1, ''),
        ),
      },
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });

  test('skipped when indexing is disabled', () async {
    final result = await task(
      probeResponses: {
        'mdutil -s /': ProcessResult.success('Indexing disabled.'),
      },
    ).run();

    expect(result.outcome, OptimizeOutcome.skipped);
  });

  test('unchanged when indexing and searching are both disabled', () async {
    final result = await task(
      probeResponses: {
        'mdutil -s /': ProcessResult.success(
          'Indexing and searching disabled.',
        ),
      },
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('skipped when enabled but running on battery', () async {
    final result = await task(
      probeResponses: {
        'mdutil -s /': ProcessResult.success('Indexing enabled.'),
        'pmset -g batt': _battery(),
      },
    ).run();

    expect(result.outcome, OptimizeOutcome.skipped);
  });

  test('unchanged when both speed probes are fast', () async {
    final result = await task(
      probeResponses: {
        'mdutil -s /': ProcessResult.success('Indexing enabled.'),
        'pmset -g batt': _acPower(),
        "mdfind kMDItemFSName == 'Applications'": _fastFind(),
      },
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('failed when a speed probe cannot run', () async {
    final result = await task(
      probeResponses: {
        'mdutil -s /': ProcessResult.success('Indexing enabled.'),
        'pmset -g batt': _acPower(),
        "mdfind kMDItemFSName == 'Applications'": ProcessResult.failure(
          ProcessFailure.nonZeroExit('mdfind', 1, ''),
        ),
      },
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });

  test(
    'both probes timing out counts as slow twice, triggering a rebuild',
    () async {
      final privileged = FakePrivilegedCommand({
        'rebuild_spotlight_index': null,
      });

      final result = await task(
        privileged: privileged,
        probeResponses: {
          'mdutil -s /': ProcessResult.success('Indexing enabled.'),
          'pmset -g batt': _acPower(),
          "mdfind kMDItemFSName == 'Applications'": ProcessResult.failure(
            ProcessFailure.timedOut('mdfind', const Duration(seconds: 10)),
          ),
        },
      ).run();

      expect(result.outcome, OptimizeOutcome.applied);
      expect(privileged.calls, ['rebuild_spotlight_index']);
    },
  );

  test('reports failed when the rebuild elevation is declined', () async {
    final result = await task(
      privileged: FakePrivilegedCommand({
        'rebuild_spotlight_index': 'declined',
      }),
      probeResponses: {
        'mdutil -s /': ProcessResult.success('Indexing enabled.'),
        'pmset -g batt': _acPower(),
        "mdfind kMDItemFSName == 'Applications'": ProcessResult.failure(
          ProcessFailure.timedOut('mdfind', const Duration(seconds: 10)),
        ),
      },
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });
}
