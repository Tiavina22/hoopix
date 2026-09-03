import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/coreduet_cleanup_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_process_runner.dart';

const _bigContent = 120 * 1024 * 1024; // over the 100MB combined threshold

void main() {
  late Directory home;
  late String dbPath;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_coreduet_');
    dbPath = '${home.path}/Library/Application Support/Knowledge/knowledgeC.db';
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> writeSized(String path, int sizeBytes) async {
    final file = File(path);
    await file.create(recursive: true);
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(sizeBytes);
    await handle.close();
  }

  test('action id matches the catalog', () async {
    final result = await CoreduetCleanupTask(
      home: home.path,
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.task.action, 'coreduet_cleanup');
  });

  test('unchanged when the Knowledge database does not exist', () async {
    final result = await CoreduetCleanupTask(
      home: home.path,
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('unchanged when the combined size is under the threshold', () async {
    await writeSized(dbPath, 1024);

    final result = await CoreduetCleanupTask(
      home: home.path,
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('unavailable when sqlite3 is missing', () async {
    await writeSized(dbPath, _bigContent);

    final result = await CoreduetCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        'sqlite3 -version': ProcessResult.failure(
          ProcessFailure.notFound('sqlite3', 'missing'),
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unavailable);
  });

  test('removes WAL/SHM sidecars and vacuums the database', () async {
    await writeSized(dbPath, _bigContent);
    final wal = File('$dbPath-wal');
    await wal.create();
    final shm = File('$dbPath-shm');
    await shm.create();

    final result = await CoreduetCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        'sqlite3 -version': ProcessResult.success('3.43.0'),
        "sqlite3 $dbPath DELETE FROM ZOBJECT WHERE ZCREATIONDATE < "
            "(strftime('%s','now','-90 days') - strftime('%s','2001-01-01')); "
            'VACUUM;': ProcessResult.success(
          '',
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
    expect(wal.existsSync(), isFalse);
    expect(shm.existsSync(), isFalse);
  });

  test('reports failed when the delete does not succeed', () async {
    await writeSized(dbPath, _bigContent);

    final result = await CoreduetCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        'sqlite3 -version': ProcessResult.success('3.43.0'),
        "sqlite3 $dbPath DELETE FROM ZOBJECT WHERE ZCREATIONDATE < "
            "(strftime('%s','now','-90 days') - strftime('%s','2001-01-01')); "
            'VACUUM;': ProcessResult.failure(
          ProcessFailure.nonZeroExit('sqlite3', 1, 'locked'),
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });
}
