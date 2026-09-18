import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/directory_scanner.dart';
import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_cache.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/large_files_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/local_snapshot_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/overview_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/reveal_local_datasource.dart';
import 'package:hoopix/features/analyze/data/datasources/trash_local_datasource.dart';
import 'package:hoopix/features/analyze/data/repositories/analyze_repository_impl.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const trashChannel = MethodChannel('fit.hoopix/trash');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_analyze_log_');
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(trashChannel, null);
    if (home.existsSync()) await home.delete(recursive: true);
  });

  /// Nothing but the Trash move is ever exercised; the other datasources are
  /// built inert, over a process runner that answers nothing.
  AnalyzeRepositoryImpl repositoryWith({OperationLog? log}) {
    final runner = FakeProcessRunner(const {});
    return AnalyzeRepositoryImpl.withDataSources(
      overview: OverviewLocalDataSource(runner, home: home.path),
      directory: DirectoryLocalDataSource(
        DirectoryScanner(),
        DirectoryCache(cacheDirectory: null),
      ),
      largeFiles: LargeFilesLocalDataSource(runner),
      reveal: RevealLocalDataSource(runner),
      trash: const TrashLocalDataSource(),
      localSnapshot: LocalSnapshotLocalDataSource(runner),
      log: log,
    );
  }

  List<Map<String, Object?>> readLog() {
    final file = File('${home.path}/Library/Logs/hoopix/operations.log');
    if (!file.existsSync()) return const [];
    return [
      for (final line in file.readAsLinesSync())
        if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
    ];
  }

  void trashAnswers(Map<String, String> failures) {
    messenger.setMockMethodCallHandler(
      trashChannel,
      (call) async => <Object?, Object?>{...failures},
    );
  }

  test('records each path moved to the Trash, and each one refused', () async {
    trashAnswers({'/Users/me/locked.txt': 'protected by macOS'});
    final repository = repositoryWith(log: OperationLog(home: home.path));

    final failures = await repository.moveToTrash([
      '/Users/me/big.iso',
      '/Users/me/locked.txt',
    ]);

    expect(failures, {'/Users/me/locked.txt': 'protected by macOS'});
    final entries = {for (final e in readLog()) e['path']: e};
    expect(entries.keys, ['/Users/me/big.iso', '/Users/me/locked.txt']);
    expect(entries['/Users/me/big.iso']!['command'], 'analyze');
    expect(entries['/Users/me/big.iso']!['outcome'], 'trashed');
    expect(entries['/Users/me/locked.txt']!['outcome'], 'refused');
    expect(entries['/Users/me/locked.txt']!['detail'], 'protected by macOS');
  });

  test('a repository built without a log never writes one', () async {
    trashAnswers(const {});
    final repository = repositoryWith();

    await repository.moveToTrash(['/Users/me/big.iso']);

    expect(readLog(), isEmpty);
    expect(
      File('${home.path}/Library/Logs/hoopix/operations.log').existsSync(),
      isFalse,
    );
  });

  test('logging never changes what the caller is told', () async {
    trashAnswers({'/a': 'nope'});
    final withLog = await repositoryWith(
      log: OperationLog(home: home.path),
    ).moveToTrash(['/a', '/b']);
    final without = await repositoryWith().moveToTrash(['/a', '/b']);

    expect(withLog, without);
  });
}
