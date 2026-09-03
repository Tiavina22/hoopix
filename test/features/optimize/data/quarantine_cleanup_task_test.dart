import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/quarantine_cleanup_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  late Directory home;
  late String dbPath;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_quarantine_');
    dbPath =
        '${home.path}/Library/Preferences/'
        'com.apple.LaunchServices.QuarantineEventsV2';
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  test('action id matches the catalog', () async {
    final result = await QuarantineCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        'sqlite3 -version': ProcessResult.success('3.43.0'),
      }),
    ).run();

    expect(result.task.action, 'quarantine_cleanup');
  });

  test('unavailable when sqlite3 is missing', () async {
    final result = await QuarantineCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        'sqlite3 -version': ProcessResult.failure(
          ProcessFailure.notFound('sqlite3', 'missing'),
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unavailable);
  });

  test('unchanged when the database file does not exist', () async {
    final result = await QuarantineCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        'sqlite3 -version': ProcessResult.success('3.43.0'),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('unchanged when the database exists — its own com.apple.* filename '
      'is protected, the same reason Mole\'s own opt_quarantine_cleanup '
      'never actually clears it either', () async {
    await File(dbPath).create(recursive: true);

    final result = await QuarantineCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        'sqlite3 -version': ProcessResult.success('3.43.0'),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });
}
