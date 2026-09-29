import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/data/repositories/whitelist_repository_impl.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_whitelist_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  test('reads null while there is no file', () async {
    expect(await WhitelistRepositoryImpl(home: home.path).read(), isNull);
  });

  test('saves into a directory it creates, and reads it back', () async {
    final repository = WhitelistRepositoryImpl(home: home.path);

    await repository.save(['# header', '', '~/.npm/_cacache/*']);

    expect(await repository.read(), ['# header', '', '~/.npm/_cacache/*']);
    expect(
      File('${home.path}/.config/hoopix/whitelist.saving').existsSync(),
      isFalse,
    );
  });

  test('replaces the previous file entirely', () async {
    final repository = WhitelistRepositoryImpl(home: home.path);

    await repository.save(['~/a/*', '~/b/*']);
    await repository.save(['~/c/*']);

    expect(await repository.read(), ['~/c/*']);
  });
}
