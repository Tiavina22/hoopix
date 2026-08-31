import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';
import 'package:hoopix/features/analyze/domain/repositories/analyze_repository.dart';
import 'package:hoopix/features/analyze/domain/usecases/find_large_files.dart';
import 'package:hoopix/features/analyze/domain/usecases/get_local_snapshot_count.dart';
import 'package:hoopix/features/analyze/domain/usecases/move_to_trash.dart';
import 'package:hoopix/features/analyze/domain/usecases/reveal_in_finder.dart';
import 'package:hoopix/features/analyze/domain/usecases/watch_directory.dart';
import 'package:hoopix/features/analyze/presentation/state/analyze_controller.dart';

const _home = '/Users/tester';

class _FakeAnalyzeRepository implements AnalyzeRepository {
  final Map<String, StreamController<DirectoryScan>> controllers = {};
  final Map<String, Completer<List<AnalyzeEntry>>> largeFileRequests = {};
  final List<String> watched = [];
  final List<String> searched = [];
  final List<String> revealed = [];

  @override
  Stream<DirectoryScan> watchOverview() => watchDirectory(overviewPath);

  @override
  Future<List<AnalyzeEntry>> findLargeFiles(String root) {
    searched.add(root);
    return largeFileRequests
        .putIfAbsent(root, Completer<List<AnalyzeEntry>>.new)
        .future;
  }

  @override
  Stream<DirectoryScan> watchDirectory(String path) {
    watched.add(path);
    return controllers
        .putIfAbsent(path, StreamController<DirectoryScan>.broadcast)
        .stream;
  }

  int? snapshotCount = 0;
  Completer<void>? snapshotCountDelay;

  @override
  Future<int?> localSnapshotCount() async {
    final delay = snapshotCountDelay;
    if (delay != null) await delay.future;
    return snapshotCount;
  }

  @override
  Future<bool> revealInFinder(String path) async {
    revealed.add(path);
    return true;
  }

  /// Paths the native side refuses, mapped to why.
  final Map<String, String> refusals = {};
  final List<List<String>> trashed = [];

  @override
  Future<Map<String, String>> moveToTrash(List<String> paths) async {
    trashed.add(paths);
    return {
      for (final path in paths)
        if (refusals[path] != null) path: refusals[path]!,
    };
  }

  void emit(String path, DirectoryScan scan) => controllers[path]!.add(scan);
}

DirectoryScan _loaded(String path) => DirectoryScan(
  path: path,
  status: DirectoryScanStatus.loaded,
  entries: [
    AnalyzeEntry(
      path: '$path/child',
      name: 'child',
      isDirectory: true,
      sizeBytes: 1024,
    ),
  ],
  totalBytes: 1024,
);

const _userLibraryRow = AnalyzeEntry(
  path: '$_home/Library',
  name: 'User Library',
  isDirectory: true,
  overviewKind: OverviewRowKind.userLibrary,
);

AnalyzeController _controller(_FakeAnalyzeRepository repository) =>
    AnalyzeController(
      WatchDirectory(repository),
      FindLargeFiles(repository),
      RevealInFinder(repository),
      MoveToTrash(repository),
      GetLocalSnapshotCount(repository),
      homePath: _home,
    );

void main() {
  test('start opens the curated overview, not a directory', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    expect(controller.isOverview, isTrue);
    expect(repository.watched, [overviewPath]);
  });

  test('a scan that lands after navigating away is discarded', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..open('$_home/a');
    addTearDown(controller.dispose);

    controller.open('$_home/b');

    // The abandoned directory finishes scanning after the user already left.
    repository.emit('$_home/a', _loaded('$_home/a'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.currentPath, '$_home/b');
    expect(controller.scan, isNull);

    repository.emit('$_home/b', _loaded('$_home/b'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.scan!.path, '$_home/b');
  });

  test('openChild navigates into directories only', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    controller.openChild(
      const AnalyzeEntry(
        path: '$_home/file.txt',
        name: 'file.txt',
        isDirectory: false,
      ),
    );
    expect(controller.isOverview, isTrue);

    controller.openChild(_userLibraryRow);
    expect(controller.currentPath, '$_home/Library');
  });

  test('crumbs trail from the overview through the row that was opened', () {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    controller.openChild(_userLibraryRow);
    controller.open('$_home/Library/Caches');

    expect(controller.crumbs.map((crumb) => crumb.path), [
      overviewPath,
      '$_home/Library',
      '$_home/Library/Caches',
    ]);
    // The entered row keeps its curated name rather than its folder name.
    expect(controller.crumbs[1].kind, OverviewRowKind.userLibrary);
    expect(controller.crumbs.first.isOverview, isTrue);
  });

  test('returning to the overview clears the drill-down root', () {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    controller.openChild(_userLibraryRow);
    controller.open(overviewPath);

    expect(controller.isOverview, isTrue);
    expect(controller.crumbs, hasLength(1));
  });

  test('an overview row outside home still anchors its own trail', () {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    controller.openChild(
      const AnalyzeEntry(
        path: '/Applications',
        name: 'Applications',
        isDirectory: true,
        overviewKind: OverviewRowKind.applications,
      ),
    );
    controller.open('/Applications/Xcode.app');

    expect(controller.crumbs.map((crumb) => crumb.path), [
      overviewPath,
      '/Applications',
      '/Applications/Xcode.app',
    ]);
  });

  test('retry re-opens the current directory', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..open('$_home/Documents');
    addTearDown(controller.dispose);

    controller.retry();

    expect(repository.watched, ['$_home/Documents', '$_home/Documents']);
  });

  test('the largest-files search starts from home while on the overview', () {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    controller.showLargeFiles();

    expect(repository.searched, [_home]);
    expect(controller.isLoadingLargeFiles, isTrue);
  });

  test('the largest-files search follows the directory drilled into', () {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    controller.openChild(_userLibraryRow);
    controller.showLargeFiles();

    expect(repository.searched, ['$_home/Library']);
  });

  test('a search that lands after navigating away is discarded', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    controller.showLargeFiles();
    // The user leaves before Spotlight answers.
    controller.openChild(_userLibraryRow);

    repository.largeFileRequests[_home]!.complete([
      const AnalyzeEntry(
        path: '$_home/big.zip',
        name: 'big.zip',
        isDirectory: false,
        sizeBytes: 500,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.largeFiles, isNull);
    expect(controller.view, AnalyzeView.entries);
  });

  test('navigating drops a loaded largest-files list', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    controller.showLargeFiles();
    repository.largeFileRequests[_home]!.complete(const []);
    await Future<void>.delayed(Duration.zero);
    expect(controller.view, AnalyzeView.largeFiles);

    controller.openChild(_userLibraryRow);

    expect(controller.view, AnalyzeView.entries);
    expect(controller.largeFiles, isNull);
  });

  test('a trashed entry re-reads the directory it came from', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..open('$_home/Documents');
    addTearDown(controller.dispose);

    final refusal = await controller.moveToTrash(
      const AnalyzeEntry(
        path: '$_home/Documents/old.zip',
        name: 'old.zip',
        isDirectory: false,
        sizeBytes: 10,
      ),
    );

    expect(refusal, isNull);
    expect(repository.trashed, [
      ['$_home/Documents/old.zip'],
    ]);
    // Re-read rather than patched in place, so the listing cannot drift.
    expect(repository.watched, ['$_home/Documents', '$_home/Documents']);
  });

  test('a refused entry reports why and leaves the listing alone', () async {
    final repository = _FakeAnalyzeRepository()
      ..refusals['/System'] = 'protected path cannot be deleted';
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    final refusal = await controller.moveToTrash(
      const AnalyzeEntry(path: '/System', name: 'System', isDirectory: true),
    );

    expect(refusal, 'protected path cannot be deleted');
    // Only the initial overview read: nothing was re-read, nothing moved.
    expect(repository.watched, [overviewPath]);
  });

  test('a trashed file refreshes the largest-files list instead', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    controller.showLargeFiles();
    repository.largeFileRequests[_home]!.complete(const []);
    await Future<void>.delayed(Duration.zero);

    await controller.moveToTrash(
      const AnalyzeEntry(
        path: '$_home/big.iso',
        name: 'big.iso',
        isDirectory: false,
        sizeBytes: 10,
      ),
    );

    expect(repository.searched, [_home, _home]);
    expect(controller.view, AnalyzeView.largeFiles);
  });

  test('the filter matches on name or path, case-insensitively', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..open('$_home/Documents');
    addTearDown(controller.dispose);

    repository.emit(
      '$_home/Documents',
      const DirectoryScan(
        path: '$_home/Documents',
        status: DirectoryScanStatus.loaded,
        entries: [
          AnalyzeEntry(
            path: '$_home/Documents/Invoices',
            name: 'Invoices',
            isDirectory: true,
            sizeBytes: 30,
          ),
          AnalyzeEntry(
            path: '$_home/Documents/photos',
            name: 'photos',
            isDirectory: true,
            sizeBytes: 20,
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    controller.setFilter('INVOI');
    expect(controller.visibleEntries.map((e) => e.name), ['Invoices']);

    // Matches the path too, not just the displayed name.
    controller.setFilter('documents/photos');
    expect(controller.visibleEntries.map((e) => e.name), ['photos']);

    controller.setFilter('');
    expect(controller.visibleEntries, hasLength(2));
  });

  test('navigating clears the filter but a delete refresh keeps it', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..open('$_home/Documents');
    addTearDown(controller.dispose);

    controller.setFilter('zip');
    await controller.moveToTrash(
      const AnalyzeEntry(
        path: '$_home/Documents/a.zip',
        name: 'a.zip',
        isDirectory: false,
      ),
    );
    expect(controller.filter, 'zip');

    controller.open('$_home/Downloads');
    expect(controller.filter, isEmpty);
  });


  test('selection is held by path, so a re-sort cannot move it', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..open('$_home/Documents');
    addTearDown(controller.dispose);

    repository.emit(
      '$_home/Documents',
      const DirectoryScan(
        path: '$_home/Documents',
        status: DirectoryScanStatus.loaded,
        entries: [
          AnalyzeEntry(
            path: '$_home/Documents/a',
            name: 'a',
            isDirectory: true,
            sizeBytes: 10,
          ),
          AnalyzeEntry(
            path: '$_home/Documents/b',
            name: 'b',
            isDirectory: true,
            sizeBytes: 20,
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    AnalyzeEntry row(String name) =>
        controller.visibleEntries.firstWhere((entry) => entry.name == name);

    controller.toggleSelection(row('a'));
    expect(controller.selectedEntries.map((e) => e.name), ['a']);
    expect(controller.selectedBytes, 10);

    controller.toggleSelection(row('b'));
    // Reported in the order the list shows them, not the order ticked.
    expect(controller.selectedEntries.map((e) => e.name), ['a', 'b']);
    expect(controller.selectedBytes, 30);

    controller.toggleSelection(row('a'));
    expect(controller.selectedEntries.map((e) => e.name), ['b']);
  });

  test('moving the selection trashes every ticked path at once', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..open('$_home/Documents');
    addTearDown(controller.dispose);

    repository.emit(
      '$_home/Documents',
      const DirectoryScan(
        path: '$_home/Documents',
        status: DirectoryScanStatus.loaded,
        entries: [
          AnalyzeEntry(
            path: '$_home/Documents/a',
            name: 'a',
            isDirectory: true,
            sizeBytes: 10,
          ),
          AnalyzeEntry(
            path: '$_home/Documents/b',
            name: 'b',
            isDirectory: true,
            sizeBytes: 20,
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    controller
      ..toggleSelection(controller.visibleEntries.first)
      ..toggleSelection(controller.visibleEntries.last);

    final failures = await controller.moveSelectedToTrash();

    expect(failures, isEmpty);
    expect(repository.trashed.single, hasLength(2));
    expect(controller.selected, isEmpty);
  });

  test('a refused path stays ticked while the rest are released', () async {
    final repository = _FakeAnalyzeRepository()
      ..refusals['$_home/Documents/b'] = 'protected path cannot be deleted';
    final controller = _controller(repository)..open('$_home/Documents');
    addTearDown(controller.dispose);

    repository.emit(
      '$_home/Documents',
      const DirectoryScan(
        path: '$_home/Documents',
        status: DirectoryScanStatus.loaded,
        entries: [
          AnalyzeEntry(
            path: '$_home/Documents/a',
            name: 'a',
            isDirectory: true,
            sizeBytes: 10,
          ),
          AnalyzeEntry(
            path: '$_home/Documents/b',
            name: 'b',
            isDirectory: true,
            sizeBytes: 20,
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    controller
      ..toggleSelection(controller.visibleEntries.first)
      ..toggleSelection(controller.visibleEntries.last);

    final failures = await controller.moveSelectedToTrash();

    expect(failures.keys, ['$_home/Documents/b']);
    // What was refused is still shown as selected; what left is not.
    expect(controller.selected, {'$_home/Documents/b'});
  });

  test('navigating drops the selection', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    controller.toggleSelection(_userLibraryRow);
    expect(controller.selected, isNotEmpty);

    controller.open('$_home/Downloads');
    expect(controller.selected, isEmpty);
  });


  test('opening the overview fetches the local snapshot count', () async {
    final repository = _FakeAnalyzeRepository()..snapshotCount = 7;
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    await Future<void>.delayed(Duration.zero);

    expect(controller.localSnapshotCount, 7);
  });

  test('leaving the overview before the probe answers discards it', () async {
    final repository = _FakeAnalyzeRepository();
    // Never completes on its own; the probe result races navigation.
    repository.snapshotCountDelay = Completer<void>();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    controller.open('$_home/Documents');
    repository.snapshotCountDelay!.complete();
    await Future<void>.delayed(Duration.zero);

    expect(controller.localSnapshotCount, isNull);
  });

  test('a failed probe leaves the count null rather than zero', () async {
    final repository = _FakeAnalyzeRepository()..snapshotCount = null;
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    await Future<void>.delayed(Duration.zero);

    expect(controller.localSnapshotCount, isNull);
  });


  test('exportJson is null until a scan has landed', () {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    expect(controller.exportJson(), isNull);
  });

  test('exportJson reflects what is currently on screen', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..open('$_home/Documents');
    addTearDown(controller.dispose);

    repository.emit('$_home/Documents', _loaded('$_home/Documents'));
    await Future<void>.delayed(Duration.zero);

    final json = controller.exportJson();

    expect(json, isNotNull);
    expect(json, contains('"child"'));
    expect(json, contains('"overview": false'));
  });

  test('reveal forwards the entry path', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    await controller.reveal(_userLibraryRow);

    expect(repository.revealed, ['$_home/Library']);
  });
}
