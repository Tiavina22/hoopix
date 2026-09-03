import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/finder_metadata_local_datasource.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_finder_metadata_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeFile(String relative) =>
      File('${home.path}/$relative').create(recursive: true);

  FinderMetadataLocalDataSource source() =>
      FinderMetadataLocalDataSource(home: home.path);

  test('section name matches the constant User essentials uses', () {
    expect(
      source().enumerate().section,
      CleanSectionsLocalDataSource.userEssentials,
    );
  });

  test(
    'reaches a .DS_Store at the top level and several levels deep',
    () async {
      await makeFile('.DS_Store');
      await makeFile('Documents/Project/.DS_Store');

      final result = source().enumerate();

      expect(
        result.paths,
        containsAll([
          '${home.path}/.DS_Store',
          '${home.path}/Documents/Project/.DS_Store',
        ]),
      );
    },
  );

  test('never matches a file merely named like .DS_Store', () async {
    await makeFile('.DS_Store.bak');
    await makeFile('MyDS_Store');

    expect(source().enumerate().paths, isEmpty);
  });

  test('stops at 5 levels deep', () async {
    await makeFile('a/b/c/d/.DS_Store');
    await makeFile('a/b/c/d/e/.DS_Store');

    final result = source().enumerate();

    expect(result.paths, ['${home.path}/a/b/c/d/.DS_Store']);
  });

  group('pruned directories', () {
    for (final pruned in [
      'Library/Application Support/MobileSync',
      'Library/Developer',
      '.Trash',
      'node_modules',
      '.git',
      'Library/Caches',
    ]) {
      test('never descends into $pruned', () async {
        await makeFile('$pruned/.DS_Store');

        expect(source().enumerate().paths, isEmpty);
      });
    }

    test(
      'prunes a nested node_modules too, not just a top-level one',
      () async {
        await makeFile('Projects/app/node_modules/.DS_Store');

        expect(source().enumerate().paths, isEmpty);
      },
    );
  });

  test('never follows a symlink', () async {
    final outside = await Directory.systemTemp.createTemp(
      'hoopix_finder_metadata_outside_',
    );
    addTearDown(() async {
      if (outside.existsSync()) await outside.delete(recursive: true);
    });
    await File('${outside.path}/.DS_Store').create();
    await Link('${home.path}/linked').create(outside.path);

    expect(source().enumerate().paths, isEmpty);
  });

  test('a missing home tree does not throw', () {
    expect(
      FinderMetadataLocalDataSource(
        home: '${home.path}/does-not-exist',
      ).enumerate().paths,
      isEmpty,
    );
  });
}
