import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/purge_discovery.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_purge_discovery_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> mkdir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);
  Future<void> touch(String relative) =>
      File('${home.path}/$relative').create(recursive: true);

  test('includes every default search path that exists', () async {
    await mkdir('Code');
    await mkdir('Projects');
    // "dev" is left absent.

    final result = PurgeDiscovery(home: home.path).discover();

    expect(result, contains('${home.path}/Code'));
    expect(result, contains('${home.path}/Projects'));
    expect(result, isNot(contains('${home.path}/dev')));
  });

  test("discovers a project container among \$HOME's own children", () async {
    await mkdir('MyStuff');
    await touch('MyStuff/package.json');

    final result = PurgeDiscovery(home: home.path).discover();

    expect(result, contains('${home.path}/MyStuff'));
  });

  test(
    'never discovers a purge target sitting directly under \$HOME '
    '(issue #1459)',
    () async {
      await mkdir('node_modules');
      await touch('node_modules/pkg/package.json');

      final result = PurgeDiscovery(home: home.path).discover();

      expect(result, isNot(contains('${home.path}/node_modules')));
    },
  );

  test('does not discover an ordinary non-project directory', () async {
    await mkdir('Desktop');
    await touch('Desktop/notes.txt');

    final result = PurgeDiscovery(home: home.path).discover();

    expect(result, isNot(contains('${home.path}/Desktop')));
  });

  test('does not double-count a default path also found by the glob', () async {
    await mkdir('Code');
    await touch('Code/package.json');

    final result = PurgeDiscovery(home: home.path).discover();

    expect(result.where((p) => p == '${home.path}/Code'), hasLength(1));
  });

  test('returns a sorted, deduplicated list', () async {
    await mkdir('Code');
    await mkdir('Projects');
    await mkdir('AProject');
    await touch('AProject/package.json');

    final result = PurgeDiscovery(home: home.path).discover();

    expect(result, orderedEquals(List.of(result)..sort()));
  });
}
