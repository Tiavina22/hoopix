import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';

import '../../support/fake_process_runner.dart';

ProcessResult _found() => ProcessResult.success('123');
ProcessResult _notFound() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _errored() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 2, 'usage'));
ProcessResult _timedOut() => ProcessResult.failure(
  ProcessFailure.timedOut('pgrep', const Duration(seconds: 2)),
);

void main() {
  test('running when the exact-name probe finds a match', () async {
    final guard = ProcessGuard(FakeProcessRunner({'pgrep -x Xcode': _found()}));

    expect(await guard.check(exactNames: ['Xcode']), ProcessLiveness.running);
  });

  test('running when a full-command-line pattern matches', () async {
    final guard = ProcessGuard(
      FakeProcessRunner({'pgrep -f /Final Cut Pro.app/': _found()}),
    );

    expect(
      await guard.check(patterns: ['/Final Cut Pro.app/']),
      ProcessLiveness.running,
    );
  });

  test('not running only once every probe confirms exit 1', () async {
    final guard = ProcessGuard(
      FakeProcessRunner({
        'pgrep -x Xcode': _notFound(),
        'pgrep -f xcodebuild': _notFound(),
      }),
    );

    expect(
      await guard.check(exactNames: ['Xcode'], patterns: ['xcodebuild']),
      ProcessLiveness.notRunning,
    );
  });

  test('unknown when a probe exits with something other than 0 or 1', () async {
    final guard = ProcessGuard(
      FakeProcessRunner({'pgrep -x tart': _errored()}),
    );

    expect(await guard.check(exactNames: ['tart']), ProcessLiveness.unknown);
  });

  test('unknown when a probe times out', () async {
    final guard = ProcessGuard(
      FakeProcessRunner({'pgrep -x tart': _timedOut()}),
    );

    expect(await guard.check(exactNames: ['tart']), ProcessLiveness.unknown);
  });

  test(
    'a later match still wins running over an earlier unknown probe',
    () async {
      final guard = ProcessGuard(
        FakeProcessRunner({
          'pgrep -x Simulator': _errored(),
          'pgrep -x Xcode': _found(),
        }),
      );

      expect(
        await guard.check(exactNames: ['Simulator', 'Xcode']),
        ProcessLiveness.running,
      );
    },
  );

  test(
    'an unknown probe is not overridden by a later confirmed absence',
    () async {
      final guard = ProcessGuard(
        FakeProcessRunner({
          'pgrep -x Simulator': _errored(),
          'pgrep -x Xcode': _notFound(),
        }),
      );

      expect(
        await guard.check(exactNames: ['Simulator', 'Xcode']),
        ProcessLiveness.unknown,
      );
    },
  );

  test('unknown when called with nothing to check', () async {
    final guard = ProcessGuard(FakeProcessRunner(const {}));

    expect(await guard.check(), ProcessLiveness.unknown);
  });
}
