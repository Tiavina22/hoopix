import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';
import 'package:hoopix/features/analyze/domain/repositories/analyze_repository.dart';
import 'package:hoopix/features/analyze/domain/usecases/find_large_files.dart';
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

  @override
  Future<bool> revealInFinder(String path) async {
    revealed.add(path);
    return true;
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

  test('reveal forwards the entry path', () async {
    final repository = _FakeAnalyzeRepository();
    final controller = _controller(repository)..start();
    addTearDown(controller.dispose);

    await controller.reveal(_userLibraryRow);

    expect(repository.revealed, ['$_home/Library']);
  });
}
