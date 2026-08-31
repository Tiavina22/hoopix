import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/analyze/data/datasources/local_snapshot_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

const _command = '/usr/bin/tmutil listlocalsnapshotdates /';

void main() {
  test('counts only the documented date rows', () async {
    final runner = FakeProcessRunner({
      _command: ProcessResult.success(
        'Snapshot dates for volume group containing disk3s5 (5 total)\n'
        '2026-03-01-091530\n'
        '2026-03-08-091530\n'
        '2026-03-14-091530\n',
      ),
    });

    expect(
      await LocalSnapshotLocalDataSource(runner).count(),
      3,
    );
  });

  test('a machine with no snapshots counts zero, not null', () async {
    final runner = FakeProcessRunner({
      _command: ProcessResult.success(
        'Snapshot dates for volume group containing disk3s5 (0 total)\n',
      ),
    });

    expect(await LocalSnapshotLocalDataSource(runner).count(), 0);
  });

  test('a failed probe reports null, not zero', () async {
    final result = await LocalSnapshotLocalDataSource(
      FakeProcessRunner({}),
    ).count();

    expect(result, isNull);
  });

  test('ignores blank lines and stray whitespace', () async {
    final runner = FakeProcessRunner({
      _command: ProcessResult.success('\n  2026-03-14-091530  \n\n'),
    });

    expect(await LocalSnapshotLocalDataSource(runner).count(), 1);
  });
}
