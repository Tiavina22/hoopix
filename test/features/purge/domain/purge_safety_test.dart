import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/purge_safety.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hoopix_purge_safety_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  group('isPurgeProjectRoot', () {
    test('true when a project indicator is present', () async {
      await File('${root.path}/package.json').create();
      expect(isPurgeProjectRoot(root.path), isTrue);
    });

    test('true when a monorepo indicator is present', () async {
      await Directory('${root.path}/.git').create();
      expect(isPurgeProjectRoot(root.path), isTrue);
    });

    test('false with no indicator present', () {
      expect(isPurgeProjectRoot(root.path), isFalse);
    });
  });

  group('isSafeProjectArtifactUnderRoot', () {
    test('a depth-1+ path is always safe', () {
      expect(
        isSafeProjectArtifactUnderRoot(
          '${root.path}/project/node_modules',
          root.path,
        ),
        isTrue,
      );
      expect(
        isSafeProjectArtifactUnderRoot(
          '${root.path}/a/b/node_modules',
          root.path,
        ),
        isTrue,
      );
    });

    test(
      'a direct child (depth 0) is safe only when the root is itself a '
      'project root',
      () async {
        expect(
          isSafeProjectArtifactUnderRoot('${root.path}/node_modules', root.path),
          isFalse,
        );

        await File('${root.path}/package.json').create();
        expect(
          isSafeProjectArtifactUnderRoot('${root.path}/node_modules', root.path),
          isTrue,
        );
      },
    );

    test('false when path is not under the root at all', () {
      expect(
        isSafeProjectArtifactUnderRoot('/somewhere/else/target', root.path),
        isFalse,
      );
    });

    test('false when the root is the filesystem root', () {
      expect(isSafeProjectArtifactUnderRoot('/node_modules', '/'), isFalse);
    });
  });

  group('isSafeProjectArtifact', () {
    test('lexically contained non-existent path is accepted at depth 1', () {
      expect(
        isSafeProjectArtifact(
          '${root.path}/project/node_modules',
          root.path,
        ),
        isTrue,
      );
    });

    test('rejects a path outside the search root', () {
      expect(
        isSafeProjectArtifact('/somewhere/else/node_modules', root.path),
        isFalse,
      );
    });

    test('re-checks physically when both sides exist as directories', () async {
      final project = await Directory('${root.path}/project').create();
      final artifact = await Directory(
        '${project.path}/node_modules',
      ).create();

      expect(isSafeProjectArtifact(artifact.path, root.path), isTrue);
    });

    test(
      'a symlinked ancestor cannot lend authority over an unrelated tree',
      () async {
        final scanRoot = await Directory('${root.path}/configured-root').create();
        final artifact = await Directory(
          '${scanRoot.path}/decoy/node_modules',
        ).create(recursive: true);

        // Both sides exist as real directories, so isSafeProjectArtifact
        // takes the physical-resolution branch; simulate the root's own
        // resolution landing somewhere that does not actually contain the
        // artifact — the shape a swapped ancestor symlink would produce.
        final result = isSafeProjectArtifact(
          artifact.path,
          scanRoot.path,
          resolvePhysicalPath: (path) =>
              path == scanRoot.path ? '/completely/unrelated' : path,
        );

        expect(result, isFalse);
      },
    );

    test('an OS alias still matches once both sides resolve physically', () async {
      final varRoot = await Directory('${root.path}/var-style-root').create();
      final artifact = await Directory(
        '${varRoot.path}/project/node_modules',
      ).create(recursive: true);

      // Both sides pick up the same "/private" alias prefix once resolved,
      // the same shape /var -> /private/var takes on real macOS.
      final result = isSafeProjectArtifact(
        artifact.path,
        varRoot.path,
        resolvePhysicalPath: (path) => '/private$path',
      );

      expect(result, isTrue);
    });
  });
}
