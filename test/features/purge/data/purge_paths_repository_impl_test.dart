import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/data/repositories/purge_paths_repository_impl.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_purge_paths_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  test('reads null with no file, then what was saved', () async {
    final repository = PurgePathsRepositoryImpl(home: home.path);
    expect(await repository.read(), isNull);

    await repository.save(['# header', '', '~/Work']);

    expect(await repository.read(), ['# header', '', '~/Work']);
    expect(PurgePathsRepositoryImpl.readLinesSync(home.path), [
      '# header',
      '',
      '~/Work',
    ]);
  });

  test('tells an existing folder from a missing one or a file', () async {
    final repository = PurgePathsRepositoryImpl(home: home.path);
    await File('${home.path}/file').create();

    expect(repository.folderExists(home.path), isTrue);
    expect(repository.folderExists('${home.path}/missing'), isFalse);
    expect(repository.folderExists('${home.path}/file'), isFalse);
  });
}
