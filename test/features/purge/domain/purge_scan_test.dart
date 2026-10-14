import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/purge_scan.dart';
import 'package:hoopix/features/purge/domain/entities/purge_target_scanner.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_purge_find_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<String> project(String relative) async {
    final dir = await Directory(
      '${home.path}/$relative',
    ).create(recursive: true);
    await File('${dir.path}/package.json').create();
    await Directory(
      '${dir.path}/node_modules/pkg/dist',
    ).create(recursive: true);
    return '${dir.path}/node_modules';
  }

  test('maps each artifact to the root it was found under', () async {
    final artifact = await project('Code/app');

    final found = findPurgeArtifacts([
      '${home.path}/Code',
    ], PurgeTargetScanner());

    expect(found, {artifact: '${home.path}/Code'});
  });

  test(
    'an artifact two overlapping roots reach keeps the first root',
    () async {
      final artifact = await project('Code/team/app');

      final found = findPurgeArtifacts([
        '${home.path}/Code/team',
        '${home.path}/Code',
      ], PurgeTargetScanner());

      expect(found, {artifact: '${home.path}/Code/team'});
    },
  );

  test('a root whose walk ran out of time contributes nothing', () async {
    await project('Code/a');
    await project('Code/b');
    var calls = 0;
    final start = DateTime(2026, 1, 1);

    final found = findPurgeArtifacts(
      ['${home.path}/Code'],
      PurgeTargetScanner(now: () => start.add(Duration(seconds: 40 * calls++))),
    );

    expect(found, isEmpty);
  });
}
