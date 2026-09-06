import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/purge_container.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hoopix_purge_container_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<Directory> makeDir(String relative) async {
    final dir = Directory('${root.path}/$relative');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> makeFile(String relative) async {
    final file = File('${root.path}/$relative');
    await file.create(recursive: true);
  }

  test('rejects a dot-prefixed directory outright', () async {
    final dir = await makeDir('.hidden');
    await makeFile('.hidden/package.json');

    expect(isProjectContainer(dir.path), isFalse);
  });

  test('rejects the reserved system-folder names', () async {
    for (final name in [
      'Library',
      'Applications',
      'Movies',
      'Music',
      'Pictures',
      'Public',
    ]) {
      final dir = await makeDir(name);
      await makeFile('$name/package.json');
      expect(isProjectContainer(dir.path), isFalse, reason: name);
    }
  });

  test(
    'never treats a purge target as a container, even full of packages '
    '(issue #1459): a stray ~/node_modules must not be scanned into as if '
    'it were a project root',
    () async {
      final dir = await makeDir('node_modules');
      await makeFile('node_modules/some-package/package.json');

      expect(isProjectContainer(dir.path), isFalse);
    },
  );

  test('rejects every other purge target basename the same way', () async {
    for (final target in const ['vendor', 'Pods', 'target', 'dist', 'build']) {
      final dir = await makeDir(target);
      await makeFile('$target/package.json');
      expect(isProjectContainer(dir.path), isFalse, reason: target);
    }
  });

  test('accepts a directory holding a project at depth 1', () async {
    final dir = await makeDir('Projects');
    await makeFile('Projects/package.json');

    expect(isProjectContainer(dir.path), isTrue);
  });

  test('accepts a directory holding a project at depth 2', () async {
    final dir = await makeDir('Projects');
    await makeFile('Projects/my-app/Cargo.toml');

    expect(isProjectContainer(dir.path), isTrue);
  });

  test('rejects a project indicator past maxDepth', () async {
    final dir = await makeDir('Projects');
    await makeFile('Projects/a/b/package.json');

    expect(isProjectContainer(dir.path, maxDepth: 2), isFalse);
  });

  test('rejects a directory with no indicator anywhere in range', () async {
    final dir = await makeDir('Projects');
    await makeFile('Projects/notes.txt');

    expect(isProjectContainer(dir.path), isFalse);
  });

  test('does not throw for a missing directory', () {
    expect(isProjectContainer('${root.path}/does-not-exist'), isFalse);
  });

  test('a .git directory alone is enough to qualify', () async {
    final dir = await makeDir('Projects');
    await makeDir('Projects/repo/.git');

    expect(isProjectContainer(dir.path), isTrue);
  });
}
