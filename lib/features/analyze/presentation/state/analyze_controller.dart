import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';
import 'package:hoopix/features/analyze/domain/usecases/find_large_files.dart';
import 'package:hoopix/features/analyze/domain/usecases/reveal_in_finder.dart';
import 'package:hoopix/features/analyze/domain/usecases/watch_directory.dart';

/// One step of the breadcrumb trail. [kind] and [label] are set only for the
/// overview row a drill-down started from, whose curated name ("User
/// Library") is not its folder name; deeper crumbs render their basename.
class AnalyzeCrumb {
  const AnalyzeCrumb({
    required this.path,
    this.label,
    this.kind,
    this.isOverview = false,
  });

  final String path;
  final String? label;
  final OverviewRowKind? kind;
  final bool isOverview;
}

/// Which list the screen is showing.
enum AnalyzeView { entries, largeFiles }

/// Drives the Analyze screen: the curated overview, the directory currently
/// drilled into, the largest-files list, and navigation between them. Pure
/// presentation state — no `du`/Spotlight knowledge lives here.
class AnalyzeController extends ChangeNotifier {
  AnalyzeController(
    this._watchDirectory,
    this._findLargeFiles,
    this._revealInFinder, {
    required this.homePath,
  });

  final WatchDirectory _watchDirectory;
  final FindLargeFiles _findLargeFiles;
  final RevealInFinder _revealInFinder;

  /// Where the largest-files search starts from while the overview — which
  /// is not itself a directory — is showing.
  final String homePath;

  StreamSubscription<DirectoryScan>? _subscription;

  /// [overviewPath] while the curated overview is showing.
  String currentPath = overviewPath;
  DirectoryScan? scan;
  Object? error;

  /// The overview row this drill-down started from — the point navigation
  /// returns to the overview from. Null while the overview itself is open.
  String? _rootPath;
  String? _rootLabel;
  OverviewRowKind? _rootKind;

  /// The path the live subscription belongs to. A scan of a directory the
  /// user has already navigated away from can still deliver events before
  /// its cancellation takes effect; comparing against this field is what
  /// keeps a stale listing from overwriting the current one.
  String? _requestedPath;

  bool get isOverview => currentPath == overviewPath;

  AnalyzeView view = AnalyzeView.entries;
  List<AnalyzeEntry>? largeFiles;
  bool isLoadingLargeFiles = false;
  Object? largeFilesError;

  /// The overview is a set of roots rather than a directory, so a search
  /// started from it covers the home directory.
  String get largeFilesRoot => isOverview ? homePath : currentPath;

  /// Tags the in-flight Spotlight query the same way [_requestedPath] tags a
  /// scan, so a result for a directory the user has left is discarded.
  String? _requestedLargeFilesRoot;

  void start() => open(overviewPath);

  void showEntries() {
    if (view == AnalyzeView.entries) return;
    view = AnalyzeView.entries;
    notifyListeners();
  }

  Future<void> showLargeFiles() async {
    view = AnalyzeView.largeFiles;
    final root = largeFilesRoot;
    _requestedLargeFilesRoot = root;
    largeFiles = null;
    largeFilesError = null;
    isLoadingLargeFiles = true;
    notifyListeners();

    try {
      final found = await _findLargeFiles(root);
      if (_requestedLargeFilesRoot != root) return;
      largeFiles = found;
    } on Object catch (error) {
      if (_requestedLargeFilesRoot != root) return;
      largeFilesError = error;
    }
    isLoadingLargeFiles = false;
    notifyListeners();
  }

  void open(String path) {
    // A listing and a file search belong to the directory they were started
    // from; moving means both are dropped rather than shown under the new one.
    view = AnalyzeView.entries;
    largeFiles = null;
    largeFilesError = null;
    isLoadingLargeFiles = false;
    _requestedLargeFilesRoot = null;

    if (path == overviewPath) {
      _rootPath = null;
      _rootLabel = null;
      _rootKind = null;
    }

    _subscription?.cancel();

    currentPath = path;
    _requestedPath = path;
    scan = null;
    error = null;
    // Breadcrumb and title move immediately; the body shows "scanning" until
    // the first listing arrives.
    notifyListeners();

    _subscription = _watchDirectory(path).listen(
      (value) {
        if (_requestedPath != path) return;
        scan = value;
        error = null;
        notifyListeners();
      },
      onError: (Object err) {
        if (_requestedPath != path) return;
        error = err;
        notifyListeners();
      },
    );
  }

  void openChild(AnalyzeEntry entry) {
    if (!entry.isDirectory) return;
    if (isOverview) {
      _rootPath = entry.path;
      _rootLabel = entry.name;
      _rootKind = entry.overviewKind;
    }
    open(entry.path);
  }

  void retry() => open(currentPath);

  Future<bool> reveal(AnalyzeEntry entry) => _revealInFinder(entry.path);

  /// Overview first, then the row that was opened, then each directory down
  /// to the one currently showing.
  List<AnalyzeCrumb> get crumbs {
    final crumbs = [const AnalyzeCrumb(path: overviewPath, isOverview: true)];

    final root = _rootPath;
    if (root == null) return crumbs;
    crumbs.add(
      AnalyzeCrumb(path: root, label: _rootLabel, kind: _rootKind),
    );

    if (currentPath == root || !currentPath.startsWith('$root/')) return crumbs;

    var accumulated = root;
    for (final segment in currentPath.substring(root.length).split('/')) {
      if (segment.isEmpty) continue;
      accumulated = '$accumulated/$segment';
      crumbs.add(AnalyzeCrumb(path: accumulated));
    }
    return crumbs;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
