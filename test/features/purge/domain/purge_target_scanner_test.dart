import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/purge_target_scanner.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hoopix_purge_scan_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<void> mkdir(String relative) =>
      Directory('${root.path}/$relative').create(recursive: true);

  test('finds a target at depth 1', () async {
    await mkdir('project/node_modules');

    final result = PurgeTargetScanner().scan(root.path);

    expect(result, contains('${root.path}/project/node_modules'));
  });

  test('finds a target at the maximum depth', () async {
    await mkdir('a/b/c/d/e/target');

    final result = PurgeTargetScanner(maxDepth: 6).scan(root.path);

    expect(result, contains('${root.path}/a/b/c/d/e/target'));
  });

  test('never reaches past maxDepth', () async {
    await mkdir('a/b/c/d/e/f/node_modules');

    final result = PurgeTargetScanner(maxDepth: 6).scan(root.path);

    expect(result, isEmpty);
  });

  test(
    'continues scanning inside a matched target, finding a nested artifact',
    () async {
      await mkdir('repo/node_modules/pkg/dist');

      final result = PurgeTargetScanner().scan(root.path);

      expect(result, contains('${root.path}/repo/node_modules'));
      expect(result, contains('${root.path}/repo/node_modules/pkg/dist'));
    },
  );

  test('never descends into .git, Library, .Trash, or Applications', () async {
    await mkdir('.git/node_modules');
    await mkdir('Library/node_modules');
    await mkdir('.Trash/node_modules');
    await mkdir('Applications/node_modules');

    final result = PurgeTargetScanner().scan(root.path);

    expect(result, isEmpty);
  });

  test('finds a directory carrying a CACHEDIR.TAG', () async {
    final cacheDir = await mkdir('project/.cache-root').then(
      (_) => Directory('${root.path}/project/.cache-root'),
    );
    await File('${cacheDir.path}/CACHEDIR.TAG').writeAsString(
      'Signature: 8a477f597d28d172789f06886806bc55',
    );

    final result = PurgeTargetScanner().scan(root.path);

    expect(result, contains(cacheDir.path));
  });

  test('does not throw for a missing root', () {
    expect(PurgeTargetScanner().scan('${root.path}/missing'), isEmpty);
  });

  test('respects minDepth, skipping a direct-child target', () async {
    await mkdir('node_modules');

    final result = PurgeTargetScanner(minDepth: 2).scan(root.path);

    expect(result, isEmpty);
  });
}
