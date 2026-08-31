import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/domain/entities/deno_cache_root.dart';

const _home = '/Users/tester';

String? root([String? denoDir]) => denoCacheRoot(home: _home, denoDir: denoDir);

void main() {
  test('defaults to Deno\'s own cache directory', () {
    expect(root(), '$_home/Library/Caches/deno');
  });

  test('honours an explicit DENO_DIR', () {
    expect(root('$_home/custom/deno'), '$_home/custom/deno');
  });

  test('refuses a relative or malformed DENO_DIR', () {
    // Refusing is what keeps the sweep from treating an unresolved root as
    // "nothing to exclude".
    expect(root('relative/deno'), isNull);
    expect(root('$_home/../deno'), isNull);
    expect(root('$_home/./deno'), isNull);
    expect(root('$_home//deno'), isNull);
  });

  test('refuses a root so broad that excluding it excludes everything', () {
    expect(root('/'), isNull);
    expect(root(_home), isNull);
    expect(root('$_home/Library'), isNull);
    expect(root('$_home/Library/Caches'), isNull);
    expect(root('$_home/.cache'), isNull);
  });

  test('strips a trailing separator', () {
    expect(root('$_home/custom/deno/'), '$_home/custom/deno');
  });
}
