import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/notification_cleanup_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_process_runner.dart';

const _bigContent = 60 * 1024 * 1024; // over the 50MB threshold

void main() {
  late Directory home;
  late String groupContainerDb;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_notif_');
    groupContainerDb =
        '${home.path}/Library/Group Containers/'
        'group.com.apple.usernoted/db2/db';
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  // Uses truncate rather than writing real bytes: this only needs to report
  // the right length via stat, and a sparse file gets there without the
  // I/O cost of actually writing tens of megabytes per test.
  Future<void> writeDb(String path, int sizeBytes) async {
    final file = File(path);
    await file.create(recursive: true);
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(sizeBytes);
    await handle.close();
  }

  test('action id matches the catalog', () async {
    final result = await NotificationCleanupTask(
      home: home.path,
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.task.action, 'notification_cleanup');
  });

  test('unavailable when neither known database path resolves', () async {
    final result = await NotificationCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        'getconf DARWIN_USER_DIR': ProcessResult.failure(
          ProcessFailure.nonZeroExit('getconf', 1, ''),
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unavailable);
  });

  test(
    'unchanged when the resolved database is under the size threshold',
    () async {
      await writeDb(groupContainerDb, 1024);

      final result = await NotificationCleanupTask(
        home: home.path,
        probe: FakeProcessRunner(const {}),
      ).run();

      expect(result.outcome, OptimizeOutcome.unchanged);
    },
  );

  test('cleans a large database and restarts NotificationCenter', () async {
    await writeDb(groupContainerDb, _bigContent);

    final result = await NotificationCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        'sqlite3 -version': ProcessResult.success('3.43.0'),
        "sqlite3 $groupContainerDb DELETE FROM record WHERE delivered_date "
            "< strftime('%s','now','-30 days'); VACUUM;": ProcessResult.success(
          '',
        ),
        'killall NotificationCenter': ProcessResult.success(''),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
  });

  test('falls back to the Darwin user directory path', () async {
    final legacyPath =
        '${home.path}/darwin-user/com.apple.notificationcenter/db2/db';
    await writeDb(legacyPath, _bigContent);

    final result = await NotificationCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        'getconf DARWIN_USER_DIR': ProcessResult.success(
          '${home.path}/darwin-user/\n',
        ),
        'sqlite3 -version': ProcessResult.success('3.43.0'),
        "sqlite3 $legacyPath DELETE FROM record WHERE delivered_date < "
            "strftime('%s','now','-30 days'); VACUUM;": ProcessResult.success(
          '',
        ),
        'killall NotificationCenter': ProcessResult.success(''),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
  });

  test('reports failed when the delete does not succeed', () async {
    await writeDb(groupContainerDb, _bigContent);

    final result = await NotificationCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        'sqlite3 -version': ProcessResult.success('3.43.0'),
        "sqlite3 $groupContainerDb DELETE FROM record WHERE delivered_date "
            "< strftime('%s','now','-30 days'); VACUUM;": ProcessResult.failure(
          ProcessFailure.nonZeroExit('sqlite3', 1, 'locked'),
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });
}
