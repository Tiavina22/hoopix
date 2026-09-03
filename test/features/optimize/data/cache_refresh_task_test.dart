import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/cache_refresh_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_process_runner.dart';

Map<String, ProcessResult> _qlSuccess() => {
  'qlmanage -r cache': ProcessResult.success(''),
  'qlmanage -r': ProcessResult.success(''),
};

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_cache_refresh_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  test('action id matches the catalog', () async {
    final result = await CacheRefreshTask(
      home: home.path,
      probe: FakeProcessRunner(_qlSuccess()),
    ).run();

    expect(result.task.action, 'cache_refresh');
  });

  test(
    'leaves the com.apple.*-named caches alone — shouldProtectPath blocks '
    'them the same way it blocks Mole\'s own opt_cache_refresh, so the '
    'qlmanage refresh is the effective part of this task, not the delete',
    () async {
      final thumbnailCache = Directory(
        '${home.path}/Library/Caches/com.apple.QuickLook.thumbnailcache',
      );
      await thumbnailCache.create(recursive: true);
      final iconStore = File(
        '${home.path}/Library/Caches/com.apple.iconservices.store',
      );
      await iconStore.create(recursive: true);

      final result = await CacheRefreshTask(
        home: home.path,
        probe: FakeProcessRunner(_qlSuccess()),
      ).run();

      // Both qlmanage refreshes still succeed and count as applied.
      expect(result.outcome, OptimizeOutcome.applied);
      expect(thumbnailCache.existsSync(), isTrue);
      expect(iconStore.existsSync(), isTrue);
    },
  );

  test('missing cache paths are not an error', () async {
    final result = await CacheRefreshTask(
      home: home.path,
      probe: FakeProcessRunner(_qlSuccess()),
    ).run();

    // Both qlmanage calls still count as applied even with nothing to
    // delete on disk.
    expect(result.outcome, OptimizeOutcome.applied);
  });

  test('reports failed when qlmanage does not run', () async {
    final result = await CacheRefreshTask(
      home: home.path,
      probe: FakeProcessRunner({
        'qlmanage -r cache': ProcessResult.failure(
          ProcessFailure.notFound('qlmanage', 'missing'),
        ),
        'qlmanage -r': ProcessResult.failure(
          ProcessFailure.notFound('qlmanage', 'missing'),
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });
}
