import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/domain/entities/normalize_targets.dart';

const _home = '/Users/tester';

List<String> normalize(List<String> paths) =>
    normalizeCleanupTargets(paths, home: _home);

void main() {
  test('drops a child listed alongside its own parent', () {
    // Deleting the parent already removes the child; keeping both would
    // count the same bytes twice.
    expect(
      normalize(['$_home/Caches/app', '$_home/Caches/app/blobs']),
      ['$_home/Caches/app'],
    );
  });

  test('keeps siblings, and paths that only share a name prefix', () {
    expect(
      normalize(['$_home/a/app', '$_home/a/app-extra']),
      ['$_home/a/app', '$_home/a/app-extra'],
    );
  });

  test('drops children regardless of the order they arrive in', () {
    expect(
      normalize([
        '$_home/c/deep/deeper',
        '$_home/a',
        '$_home/c',
        '$_home/a/child',
      ]),
      ['$_home/a', '$_home/c'],
    );
  });

  test('removes duplicates, including a trailing-slash spelling', () {
    expect(
      normalize(['$_home/a', '$_home/a/', '$_home/a']),
      ['$_home/a'],
    );
  });

  test('collapses a Gradle DSL cache path to its hash directory', () {
    expect(
      normalize(['$_home/.gradle/caches/8.5/kotlin-dsl/abc123/classes/Build.class']),
      ['$_home/.gradle/caches/8.5/kotlin-dsl/abc123'],
    );
    expect(
      normalize(['$_home/.gradle/caches/8.5/groovy-dsl/def456/metadata.bin']),
      ['$_home/.gradle/caches/8.5/groovy-dsl/def456'],
    );
  });

  test('several paths under one Gradle hash directory collapse to one entry', () {
    expect(
      normalize([
        '$_home/.gradle/caches/8.5/kotlin-dsl/abc/classes/A.class',
        '$_home/.gradle/caches/8.5/kotlin-dsl/abc/metadata.bin',
      ]),
      ['$_home/.gradle/caches/8.5/kotlin-dsl/abc'],
    );
  });

  test('leaves other Gradle cache paths alone', () {
    // Not a DSL directory, so there is nothing to collapse to.
    expect(
      normalize(['$_home/.gradle/caches/modules-2/files-2.1/lib.jar']),
      ['$_home/.gradle/caches/modules-2/files-2.1/lib.jar'],
    );
    // Already at the hash directory.
    expect(
      normalize(['$_home/.gradle/caches/8.5/kotlin-dsl/abc']),
      ['$_home/.gradle/caches/8.5/kotlin-dsl/abc'],
    );
  });

  test('an empty batch stays empty', () {
    expect(normalize([]), isEmpty);
  });
}
