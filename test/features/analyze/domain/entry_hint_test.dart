import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/entry_hint.dart';

AnalyzeEntry _directory(String path) => AnalyzeEntry(
  path: path,
  name: path.split('/').last,
  isDirectory: true,
);

void main() {
  group('isCleanableDirectory', () {
    test('marks dependency and build directories', () {
      expect(isCleanableDirectory(_directory('/p/node_modules')), isTrue);
      expect(isCleanableDirectory(_directory('/p/DerivedData')), isTrue);
      expect(isCleanableDirectory(_directory('/p/.dart_tool')), isTrue);
    });

    test('leaves ordinary directories alone', () {
      expect(isCleanableDirectory(_directory('/p/Documents')), isFalse);
      expect(isCleanableDirectory(_directory('/p/src')), isFalse);
    });

    test('never marks a file', () {
      expect(
        isCleanableDirectory(
          const AnalyzeEntry(
            path: '/p/build',
            name: 'build',
            isDirectory: false,
          ),
        ),
        isFalse,
      );
    });

    test('defers to mo clean on the paths it already owns', () {
      // Same name, but inside a tree the cleanup command handles — the two
      // must not both claim it.
      expect(
        isCleanableDirectory(_directory('/Users/t/Library/Caches/build')),
        isFalse,
      );
      expect(isCleanableDirectory(_directory('/Users/t/.Trash/dist')), isFalse);
    });

    test('honours a CACHEDIR.TAG on an otherwise ordinary name', () async {
      final root = await Directory.systemTemp.createTemp('hoopix_tag_');
      addTearDown(() => root.delete(recursive: true));

      final tagged = await Directory('${root.path}/blobs').create();
      await File(
        '${tagged.path}/CACHEDIR.TAG',
      ).writeAsString('Signature: 8a477f597d28d172789f06886806bc55\n# notes');

      expect(isCleanableDirectory(_directory(tagged.path)), isTrue);
    });

    test('ignores a CACHEDIR.TAG whose signature does not match', () async {
      final root = await Directory.systemTemp.createTemp('hoopix_tag_');
      addTearDown(() => root.delete(recursive: true));

      final tagged = await Directory('${root.path}/blobs').create();
      await File('${tagged.path}/CACHEDIR.TAG').writeAsString('not the tag');

      expect(isCleanableDirectory(_directory(tagged.path)), isFalse);
    });
  });

  group('unusedForLabel', () {
    final now = DateTime(2026, 6, 1);

    test('says nothing below 90 days', () {
      expect(
        unusedForLabel(now.subtract(const Duration(days: 89)), now: now),
        isNull,
      );
      expect(unusedForLabel(null, now: now), isNull);
    });

    test('reports months once past a quarter', () {
      expect(
        unusedForLabel(now.subtract(const Duration(days: 120)), now: now),
        '>4mo',
      );
    });

    test('reports years once past one', () {
      expect(
        unusedForLabel(now.subtract(const Duration(days: 400)), now: now),
        '>1yr',
      );
      expect(
        unusedForLabel(now.subtract(const Duration(days: 800)), now: now),
        '>2yr',
      );
    });
  });
}
