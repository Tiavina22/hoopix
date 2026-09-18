import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/features/history/data/repositories/history_repository_impl.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_history_repo_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  test('reads what OperationLog actually wrote, newest first, mapped to '
      'OperationOutcome', () async {
    final log = OperationLog(home: home.path);
    log.record(
      command: 'uninstall',
      outcome: OperationOutcome.refused,
      targetPath: '/Applications/CapCut.app',
      detail: 'you don’t have permission to access it',
      sizeBytes: 1495638016,
    );
    log.record(
      command: 'clean',
      outcome: OperationOutcome.trashed,
      targetPath: '/Users/me/Library/Caches/App',
    );

    final repository = HistoryRepositoryImpl(home: home.path);
    final entries = await repository.recentOperations();

    expect(entries, hasLength(2));
    expect(entries.first.path, '/Users/me/Library/Caches/App');
    expect(entries.first.outcome, OperationOutcome.trashed);
    expect(entries.first.command, 'clean');
    expect(entries.first.detail, isNull);

    expect(entries.last.path, '/Applications/CapCut.app');
    expect(entries.last.outcome, OperationOutcome.refused);
    expect(entries.last.detail, 'you don’t have permission to access it');
    expect(entries.last.sizeBytes, 1495638016);
  });

  test(
    'an outcome OperationLog never writes is left out, not thrown',
    () async {
      final file = File(OperationLog(home: home.path).path);
      await file.create(recursive: true);
      await file.writeAsString(
        '{"at":"2026-01-01T00:00:00.000","command":"uninstall",'
        '"outcome":"exploded","path":"/x"}\n'
        '{"at":"2026-01-01T00:00:01.000","command":"uninstall",'
        '"outcome":"trashed","path":"/y"}\n',
      );

      final repository = HistoryRepositoryImpl(home: home.path);
      final entries = await repository.recentOperations();

      expect(entries.map((e) => e.path), ['/y']);
    },
  );

  test('no log file yet is an empty history, not an error', () async {
    final repository = HistoryRepositoryImpl(home: home.path);

    expect(await repository.recentOperations(), isEmpty);
  });

  test('respects a caller-supplied limit', () async {
    final log = OperationLog(home: home.path);
    for (var i = 0; i < 5; i++) {
      log.record(
        command: 'clean',
        outcome: OperationOutcome.trashed,
        targetPath: '/item-$i',
      );
    }

    final repository = HistoryRepositoryImpl(home: home.path);
    final entries = await repository.recentOperations(limit: 2);

    expect(entries.map((e) => e.path), ['/item-4', '/item-3']);
  });
}
