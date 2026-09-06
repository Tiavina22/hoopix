import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/purge_activity.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hoopix_purge_activity_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<void> backdate(FileSystemEntity entity, Duration age) async {
    final target = DateTime.now().subtract(age);
    if (entity is File) {
      await entity.setLastModified(target);
    } else {
      final stamp =
          '${target.year.toString().padLeft(4, '0')}'
          '${target.month.toString().padLeft(2, '0')}'
          '${target.day.toString().padLeft(2, '0')}'
          '${target.hour.toString().padLeft(2, '0')}'
          '${target.minute.toString().padLeft(2, '0')}';
      await Process.run('touch', ['-t', stamp, entity.path]);
    }
  }

  test('old when the path does not exist', () {
    final classifier = PurgeActivityClassifier();
    expect(classifier.classify('${root.path}/missing'), PurgeActivityState.old);
  });

  test('recent when the top-level mtime is under the age floor', () async {
    final dir = Directory('${root.path}/project')..createSync();
    await backdate(dir, const Duration(days: 1));

    final classifier = PurgeActivityClassifier();
    expect(classifier.classify(dir.path), PurgeActivityState.recent);
  });

  test('old for a plain file past the age floor', () async {
    final file = File('${root.path}/artifact.log')..createSync();
    await backdate(file, const Duration(days: 30));

    final classifier = PurgeActivityClassifier();
    expect(classifier.classify(file.path), PurgeActivityState.old);
  });

  test(
    'old for a directory past the floor with nothing recent inside',
    () async {
      final dir = Directory('${root.path}/project')..createSync();
      final file = File('${dir.path}/leftover.txt')..createSync();
      await backdate(dir, const Duration(days: 30));
      await backdate(file, const Duration(days: 30));

      final classifier = PurgeActivityClassifier();
      expect(classifier.classify(dir.path), PurgeActivityState.old);
    },
  );

  test('recent when the top-level mtime is old but a nested file was just '
      'touched — a directory\'s own mtime does not change when a deep file '
      'is edited', () async {
    final dir = Directory('${root.path}/project')..createSync();
    final nested = Directory('${dir.path}/src')..createSync();
    File('${nested.path}/main.dart').createSync();
    await backdate(dir, const Duration(days: 30));
    await backdate(nested, const Duration(days: 30));
    // freshFile keeps its just-created (recent) mtime.

    final classifier = PurgeActivityClassifier();
    expect(classifier.classify(dir.path), PurgeActivityState.recent);
  });

  test('uncertain when the probe cannot finish within its budget', () async {
    final dir = Directory('${root.path}/project')..createSync();
    await backdate(dir, const Duration(days: 30));

    final classifier = PurgeActivityClassifier(probeTimeout: Duration.zero);
    expect(classifier.classify(dir.path), PurgeActivityState.uncertain);
  });
}
