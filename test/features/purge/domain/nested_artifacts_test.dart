import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/purge/domain/entities/nested_artifacts.dart';

void main() {
  test('keeps independent artifacts separate', () {
    final result = filterNestedArtifacts([
      '/a/project/node_modules',
      '/b/project/target',
    ]);

    expect(result, unorderedEquals(['/a/project/node_modules', '/b/project/target']));
  });

  test('collapses a nested artifact into its outermost ancestor', () {
    final result = filterNestedArtifacts([
      '/repo/node_modules',
      '/repo/node_modules/some-package/dist',
    ]);

    expect(result, ['/repo/node_modules']);
  });

  test('collapses an arbitrarily deep chain in one pass', () {
    final result = filterNestedArtifacts([
      '/repo/node_modules',
      '/repo/node_modules/pkg/build',
      '/repo/node_modules/pkg/build/dist',
      '/repo/node_modules/pkg/build/dist/cache',
    ]);

    expect(result, ['/repo/node_modules']);
  });

  test('does not treat a sibling with a shared prefix as nested', () {
    final result = filterNestedArtifacts(['/repo/build', '/repo/build-tools/dist']);

    expect(
      result,
      unorderedEquals(['/repo/build', '/repo/build-tools/dist']),
    );
  });

  test('is order-independent', () {
    final ordered = filterNestedArtifacts([
      '/repo/node_modules',
      '/repo/node_modules/pkg/dist',
    ]);
    final reversed = filterNestedArtifacts([
      '/repo/node_modules/pkg/dist',
      '/repo/node_modules',
    ]);

    expect(ordered, reversed);
  });

  test('handles an empty list', () {
    expect(filterNestedArtifacts(const []), isEmpty);
  });
}
