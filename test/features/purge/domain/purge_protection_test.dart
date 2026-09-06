import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/purge_protection.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hoopix_purge_protection_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<void> touch(String relative) async {
    final file = File('${root.path}/$relative');
    await file.create(recursive: true);
  }

  Future<void> mkdir(String relative) async {
    await Directory('${root.path}/$relative').create(recursive: true);
  }

  group('bin/', () {
    test('protected by default (not a recognized .NET build dir)', () async {
      await mkdir('app/bin');

      expect(isProtectedPurgeArtifact('${root.path}/app/bin'), isTrue);
    });

    test('eligible when the parent is a .NET project with Debug/Release', () async {
      await touch('app/App.csproj');
      await mkdir('app/bin/Debug');

      expect(isProtectedPurgeArtifact('${root.path}/app/bin'), isFalse);
    });

    test('still protected without a Debug/Release subdirectory', () async {
      await touch('app/App.csproj');
      await mkdir('app/bin');

      expect(isProtectedPurgeArtifact('${root.path}/app/bin'), isTrue);
    });
  });

  group('vendor/', () {
    test('eligible under a PHP Composer project', () async {
      await touch('app/composer.json');
      await mkdir('app/vendor');

      expect(isProtectedPurgeArtifact('${root.path}/app/vendor'), isFalse);
    });

    test('protected under a Rails project', () async {
      await touch('app/config/application.rb');
      await touch('app/Gemfile');
      await touch('app/bin/rails');
      await mkdir('app/vendor');

      expect(isProtectedPurgeArtifact('${root.path}/app/vendor'), isTrue);
    });

    test('protected under a Go project', () async {
      await touch('app/go.mod');
      await mkdir('app/vendor');

      expect(isProtectedPurgeArtifact('${root.path}/app/vendor'), isTrue);
    });

    test('protected by default for an unrecognized owner', () async {
      await mkdir('app/vendor');

      expect(isProtectedPurgeArtifact('${root.path}/app/vendor'), isTrue);
    });
  });

  group('DerivedData', () {
    test('eligible under Xcode\'s own global cache path', () async {
      const path =
          '/Users/tester/Library/Developer/Xcode/DerivedData/App-abcdef';

      expect(isProtectedPurgeArtifact(path), isFalse);
    });

    test('protected everywhere else', () async {
      expect(
        isProtectedPurgeArtifact('${root.path}/somewhere/DerivedData'),
        isTrue,
      );
    });
  });

  test('every other target name is never protected by this function', () {
    for (final target in const ['node_modules', 'target', 'dist', 'build']) {
      expect(isProtectedPurgeArtifact('${root.path}/$target'), isFalse);
    }
  });

  test('tolerates a trailing slash', () async {
    await touch('app/composer.json');
    await mkdir('app/vendor');

    expect(isProtectedPurgeArtifact('${root.path}/app/vendor/'), isFalse);
  });
}
