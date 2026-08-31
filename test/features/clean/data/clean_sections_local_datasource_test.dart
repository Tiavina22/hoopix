import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_clean_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> make(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  List<String> targetsOf(CleanSectionsLocalDataSource source) =>
      source.enumerate().single.paths;

  CleanSectionsLocalDataSource source({String? denoDir}) =>
      CleanSectionsLocalDataSource(home: home.path, denoDir: denoDir);

  test('sweeps each child of the user cache directory', () async {
    await make('Library/Caches/com.example.app');
    await make('Library/Caches/another-tool');

    final targets = targetsOf(source());

    expect(targets, contains('${home.path}/Library/Caches/com.example.app'));
    expect(targets, contains('${home.path}/Library/Caches/another-tool'));
    // The directory itself is never a target — only its children.
    expect(targets, isNot(contains('${home.path}/Library/Caches')));
  });

  test('leaves the Deno root out of the sweep', () async {
    await make('Library/Caches/deno');
    await make('Library/Caches/com.example.app');

    final targets = targetsOf(source());

    // Review-only: `deno clean` would take runtime payloads with it.
    expect(targets, isNot(contains('${home.path}/Library/Caches/deno')));
    expect(targets, contains('${home.path}/Library/Caches/com.example.app'));
  });

  test('an unresolvable DENO_DIR empties the cache batch rather than sweep it', () async {
    await make('Library/Caches/com.example.app');
    await make('Library/Logs/SomeApp');

    final targets = targetsOf(source(denoDir: 'relative/deno'));

    // Sweeping past an unresolved owner root is worse than cleaning nothing.
    expect(targets.any((p) => p.contains('/Library/Caches/')), isFalse);
    // The unrelated categories still work.
    expect(targets, contains('${home.path}/Library/Logs/SomeApp'));
  });

  test('sweeps user log directories', () async {
    await make('Library/Logs/SomeApp');

    expect(targetsOf(source()), contains('${home.path}/Library/Logs/SomeApp'));
  });

  test('proposes the recent-items lists', () async {
    final targets = targetsOf(source());

    expect(
      targets,
      contains(
        '${home.path}/Library/Application Support/com.apple.sharedfilelist'
        '/com.apple.LSSharedFileList.RecentApplications.sfl2',
      ),
    );
    expect(
      targets,
      contains('${home.path}/Library/Preferences/com.apple.recentitems.plist'),
    );
  });

  test('a missing cache directory is not an error', () {
    // Nothing to list; the section simply proposes what it can.
    expect(() => targetsOf(source()), returnsNormally);
  });

  test('lists a symlink without following it', () async {
    await make('Library/Caches/real');
    await Link('${home.path}/Library/Caches/alias').create('${home.path}/Library/Caches/real');

    final targets = targetsOf(source());

    // The link is a target in its own right; the funnel decides its fate.
    expect(targets, contains('${home.path}/Library/Caches/alias'));
  });
}
