import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/cachedir_tag.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hoopix_cachedir_tag_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('true for a file starting with the exact signature', () async {
    final file = File('${root.path}/CACHEDIR.TAG');
    await file.writeAsString(
      'Signature: 8a477f597d28d172789f06886806bc55\n# more text',
    );

    expect(hasCachedirTag(root.path), isTrue);
  });

  test('false when the tag file is missing', () {
    expect(hasCachedirTag(root.path), isFalse);
  });

  test('false when the content does not match the signature', () async {
    final file = File('${root.path}/CACHEDIR.TAG');
    await file.writeAsString('not a real cache tag');

    expect(hasCachedirTag(root.path), isFalse);
  });

  test('false for an empty tag file', () async {
    final file = File('${root.path}/CACHEDIR.TAG');
    await file.create();

    expect(hasCachedirTag(root.path), isFalse);
  });

  test('false when the tag path is a symlink', () async {
    final real = File('${root.path}/real-tag');
    await real.writeAsString('Signature: 8a477f597d28d172789f06886806bc55');
    final link = Link('${root.path}/CACHEDIR.TAG');
    await link.create(real.path);

    expect(hasCachedirTag(root.path), isFalse);
  });

  test('false when the tag path is a directory', () async {
    await Directory('${root.path}/CACHEDIR.TAG').create();

    expect(hasCachedirTag(root.path), isFalse);
  });
}
