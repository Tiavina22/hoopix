import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/sqlite_vacuum_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _running() => ProcessResult.success('123\n');
ProcessResult _unexpectedPgrepFailure() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 2, 'usage'));
ProcessResult _pgrepMissing() =>
    ProcessResult.failure(ProcessFailure.notFound('pgrep', 'missing'));

Map<String, ProcessResult> _allAppsIdle() => {
  'pgrep -x Mail': _notRunning(),
  'pgrep -x Safari': _notRunning(),
  'pgrep -x Messages': _notRunning(),
};

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_sqlite_vacuum_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<File> chatDb() async {
    final file = File('${home.path}/Library/Messages/chat.db');
    await file.create(recursive: true);
    return file;
  }

  test('action id matches the catalog', () async {
    final result = await SqliteVacuumTask(
      home: home.path,
      probe: FakeProcessRunner({
        ..._allAppsIdle(),
        'sqlite3 -version': _pgrepMissing(),
      }),
    ).run();

    expect(result.task.action, 'sqlite_vacuum');
  });

  test('skipped when any of the three apps is running', () async {
    final result = await SqliteVacuumTask(
      home: home.path,
      probe: FakeProcessRunner({'pgrep -x Mail': _running()}),
    ).run();

    expect(result.outcome, OptimizeOutcome.skipped);
  });

  test('unavailable when pgrep itself is missing', () async {
    final result = await SqliteVacuumTask(
      home: home.path,
      probe: FakeProcessRunner({'pgrep -x Mail': _pgrepMissing()}),
    ).run();

    expect(result.outcome, OptimizeOutcome.unavailable);
  });

  test('failed when a busy-app probe cannot be trusted', () async {
    final result = await SqliteVacuumTask(
      home: home.path,
      probe: FakeProcessRunner({'pgrep -x Mail': _unexpectedPgrepFailure()}),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });

  test('unavailable when sqlite3 itself is missing', () async {
    final result = await SqliteVacuumTask(
      home: home.path,
      probe: FakeProcessRunner({
        ..._allAppsIdle(),
        'sqlite3 -version': _pgrepMissing(),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unavailable);
  });

  test('vacuums a compactable database and reports applied', () async {
    final db = await chatDb();

    final result = await SqliteVacuumTask(
      home: home.path,
      probe: FakeProcessRunner({
        ..._allAppsIdle(),
        'sqlite3 -version': ProcessResult.success('3.43.0'),
        'file -b ${db.path}': ProcessResult.success('SQLite 3.x database'),
        'sqlite3 ${db.path} PRAGMA page_count; PRAGMA freelist_count;':
            ProcessResult.success('1000\n900'),
        'sqlite3 ${db.path} PRAGMA integrity_check;': ProcessResult.success(
          'ok',
        ),
        'sqlite3 ${db.path} VACUUM;': ProcessResult.success(''),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
  });

  test('skips a candidate that is not actually a SQLite file', () async {
    await chatDb();

    final result = await SqliteVacuumTask(
      home: home.path,
      probe: FakeProcessRunner({
        ..._allAppsIdle(),
        'sqlite3 -version': ProcessResult.success('3.43.0'),
        'file -b ${home.path}/Library/Messages/chat.db': ProcessResult.success(
          'empty',
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('policy-skips a database over the 100MB ceiling', () async {
    final db = await chatDb();
    final handle = await File(db.path).open(mode: FileMode.write);
    await handle.truncate(101 * 1024 * 1024);
    await handle.close();

    final result = await SqliteVacuumTask(
      home: home.path,
      probe: FakeProcessRunner({
        ..._allAppsIdle(),
        'sqlite3 -version': ProcessResult.success('3.43.0'),
        'file -b ${db.path}': ProcessResult.success('SQLite 3.x database'),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.skipped);
  });

  test('leaves an already-compact database alone', () async {
    final db = await chatDb();

    final result = await SqliteVacuumTask(
      home: home.path,
      probe: FakeProcessRunner({
        ..._allAppsIdle(),
        'sqlite3 -version': ProcessResult.success('3.43.0'),
        'file -b ${db.path}': ProcessResult.success('SQLite 3.x database'),
        // freelist under 5% of pages: 10 * 100 < 1000 * 5.
        'sqlite3 ${db.path} PRAGMA page_count; PRAGMA freelist_count;':
            ProcessResult.success('1000\n10'),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('reports failed when the integrity check does not pass', () async {
    final db = await chatDb();

    final result = await SqliteVacuumTask(
      home: home.path,
      probe: FakeProcessRunner({
        ..._allAppsIdle(),
        'sqlite3 -version': ProcessResult.success('3.43.0'),
        'file -b ${db.path}': ProcessResult.success('SQLite 3.x database'),
        'sqlite3 ${db.path} PRAGMA page_count; PRAGMA freelist_count;':
            ProcessResult.success('1000\n900'),
        'sqlite3 ${db.path} PRAGMA integrity_check;': ProcessResult.success(
          'corruption found',
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });

  test('never touches a -wal or -shm sidecar directly', () async {
    final db = await chatDb();
    final wal = File('${db.path}-wal');
    await wal.create();

    final result = await SqliteVacuumTask(
      home: home.path,
      probe: FakeProcessRunner({
        ..._allAppsIdle(),
        'sqlite3 -version': ProcessResult.success('3.43.0'),
        'file -b ${db.path}': ProcessResult.success('empty'),
      }),
    ).run();

    // No fake response configured for `file -b` on the wal file: if the
    // task ever queried it, FakeProcessRunner's own "no fake response"
    // failure would surface as a `failed` outcome instead of `unchanged`.
    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('discovers an Envelope Index file under a V* Mail account dir, but '
      'never vacuums it — shouldProtectPath blocks everything under '
      '~/Library/Mail, the same reason Mole\'s own opt_sqlite_vacuum never '
      'actually compacts Mail either', () async {
    final envelope = File(
      '${home.path}/Library/Mail/V10/MailData/Envelope Index',
    );
    await envelope.create(recursive: true);

    final result = await SqliteVacuumTask(
      home: home.path,
      probe: FakeProcessRunner({
        ..._allAppsIdle(),
        'sqlite3 -version': ProcessResult.success('3.43.0'),
      }),
    ).run();

    // No fake response configured for `file -b` on the envelope path: if
    // the task ever queried it (meaning shouldProtectPath failed to
    // block it), FakeProcessRunner's "no fake response" failure would
    // surface as `failed` instead of `unchanged`.
    expect(result.outcome, OptimizeOutcome.unchanged);
  });
}
