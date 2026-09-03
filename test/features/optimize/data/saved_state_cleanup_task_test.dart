import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/optimize/data/datasources/saved_state_cleanup_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_saved_state_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<Directory> savedStateDir(String appName) async {
    final dir = Directory(
      '${home.path}/Library/Saved Application State/$appName.savedState',
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> backdate(Directory dir, Duration age) async {
    final target = DateTime.now().subtract(age);
    final stamp =
        '${target.year.toString().padLeft(4, '0')}'
        '${target.month.toString().padLeft(2, '0')}'
        '${target.day.toString().padLeft(2, '0')}'
        '${target.hour.toString().padLeft(2, '0')}'
        '${target.minute.toString().padLeft(2, '0')}';
    await Process.run('touch', ['-t', stamp, dir.path]);
  }

  test('action id matches the catalog', () async {
    final result = await SavedStateCleanupTask(home: home.path).run();
    expect(result.task.action, 'saved_state_cleanup');
  });

  test(
    'unchanged when the Saved Application State directory is missing',
    () async {
      final result = await SavedStateCleanupTask(home: home.path).run();
      expect(result.outcome, OptimizeOutcome.unchanged);
    },
  );

  test('removes a bundle untouched for 30+ days', () async {
    final old = await savedStateDir('com.example.Old');
    await backdate(old, const Duration(days: 40));

    final result = await SavedStateCleanupTask(home: home.path).run();

    expect(result.outcome, OptimizeOutcome.applied);
    expect(old.existsSync(), isFalse);
  });

  test('leaves a bundle touched within the last 30 days alone', () async {
    final recent = await savedStateDir('com.example.Recent');
    await backdate(recent, const Duration(days: 5));

    final result = await SavedStateCleanupTask(home: home.path).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
    expect(recent.existsSync(), isTrue);
  });

  test('ignores an entry that is not a .savedState directory', () async {
    final root = Directory('${home.path}/Library/Saved Application State');
    await root.create(recursive: true);
    final stray = File('${root.path}/notes.txt');
    await stray.create();
    await stray.setLastModified(
      DateTime.now().subtract(const Duration(days: 90)),
    );

    final result = await SavedStateCleanupTask(home: home.path).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
    expect(stray.existsSync(), isTrue);
  });
}
