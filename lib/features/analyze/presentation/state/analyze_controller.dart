import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';
import 'package:hoopix/features/analyze/domain/usecases/build_analyze_json.dart';
import 'package:hoopix/features/analyze/domain/usecases/find_large_files.dart';
import 'package:hoopix/features/analyze/domain/usecases/get_local_snapshot_count.dart';
import 'package:hoopix/features/analyze/domain/usecases/move_to_trash.dart';
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
    this._revealInFinder,
    this._moveToTrash,
    this._getLocalSnapshotCount, {
    required this.homePath,
  });

  final WatchDirectory _watchDirectory;
  final FindLargeFiles _findLargeFiles;
  final RevealInFinder _revealInFinder;
  final MoveToTrash _moveToTrash;
  final GetLocalSnapshotCount _getLocalSnapshotCount;

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

  /// Local Time Machine snapshots quietly hold space no row in the listing
  /// accounts for, so the overview says how many exist. Null until the
  /// probe answers, or when it fails — both read as "say nothing".
  int? localSnapshotCount;

  /// Invalidates an in-flight snapshot probe the moment navigation moves on,
  /// the same pattern [_requestedPath] uses for the directory stream.
  int _snapshotRequestId = 0;

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

  /// Rows ticked for a batch action, held by path rather than by index so a
  /// list that re-sorts under them cannot move the selection onto something
  /// else.
  final Set<String> selected = {};

  bool isSelected(AnalyzeEntry entry) => selected.contains(entry.path);

  void toggleSelection(AnalyzeEntry entry) {
    if (!selected.remove(entry.path)) selected.add(entry.path);
    notifyListeners();
  }

  void clearSelection() {
    if (selected.isEmpty) return;
    selected.clear();
    notifyListeners();
  }

  /// The ticked rows, in the order they are shown.
  List<AnalyzeEntry> get selectedEntries => [
    for (final entry in visibleEntries)
      if (selected.contains(entry.path)) entry,
  ];

  /// Total of the ticked rows whose size is known.
  int get selectedBytes => selectedEntries.fold(
    0,
    (total, entry) => total + (entry.sizeBytes ?? 0),
  );

  /// Case-insensitive substring, matched against the row's name or its path,
  /// applied to whichever list is showing. Empty means no filter.
  String filter = '';

  void setFilter(String value) {
    if (filter == value) return;
    filter = value;
    notifyListeners();
  }

  List<AnalyzeEntry> _filtered(List<AnalyzeEntry> entries) {
    if (filter.isEmpty) return entries;
    final needle = filter.toLowerCase();
    return [
      for (final entry in entries)
        if (entry.name.toLowerCase().contains(needle) ||
            entry.path.toLowerCase().contains(needle))
          entry,
    ];
  }

  /// The rows to render: the current listing or file list, filtered.
  List<AnalyzeEntry> get visibleEntries => _filtered(
    view == AnalyzeView.largeFiles
        ? (largeFiles ?? const [])
        : (scan?.entries ?? const []),
  );

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

  /// Navigates to [path]: the view, the file search and the filter all
  /// belonged to where the user was, not to where they are going.
  void open(String path) {
    view = AnalyzeView.entries;
    largeFiles = null;
    largeFilesError = null;
    isLoadingLargeFiles = false;
    _requestedLargeFilesRoot = null;
    filter = '';
    selected.clear();
    _reload(path);
  }

  /// Re-reads the current directory without disturbing the view or the
  /// filter — what a refresh after a delete needs.
  void _reload(String path) {
    // Bumped unconditionally, so a probe already in flight can never land
    // after navigation moved on to somewhere it no longer applies.
    _snapshotRequestId++;

    if (path == overviewPath) {
      _rootPath = null;
      _rootLabel = null;
      _rootKind = null;
      localSnapshotCount = null;
      unawaited(_fetchLocalSnapshotCount());
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

  Future<void> _fetchLocalSnapshotCount() async {
    final requestId = _snapshotRequestId;
    final count = await _getLocalSnapshotCount();
    if (requestId != _snapshotRequestId) return;
    localSnapshotCount = count;
    notifyListeners();
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

  /// The current listing as JSON, matching Mole's `--json` field names —
  /// see [buildAnalyzeJson] for the one scope difference. Null while nothing
  /// has loaded yet.
  String? exportJson() {
    final current = scan;
    if (current == null) return null;
    return buildAnalyzeJson(current, isOverview: isOverview, largeFiles: largeFiles);
  }

  Future<bool> reveal(AnalyzeEntry entry) => _revealInFinder(entry.path);

  /// Moves [entry] to the Trash and refreshes the view it came from.
  ///
  /// Returns the reason it was refused, or null when it was moved. The
  /// refusal comes from the native side, which is where the protected-path
  /// rules live — this only reports it.
  Future<String?> moveToTrash(AnalyzeEntry entry) async {
    final failures = await _trash([entry.path]);
    return failures[entry.path];
  }

  /// Moves every ticked row. Returns the ones that were refused, mapped to
  /// why; a refusal for one never stops the others.
  Future<Map<String, String>> moveSelectedToTrash() async {
    final paths = selectedEntries.map((entry) => entry.path).toList();
    if (paths.isEmpty) return const {};

    final failures = await _trash(paths);
    // Anything that actually left stops being selected; what was refused
    // stays ticked so the user can see what did not go.
    selected.removeWhere((path) => !failures.containsKey(path));
    notifyListeners();
    return failures;
  }

  Future<Map<String, String>> _trash(List<String> paths) async {
    final failures = await _moveToTrash(paths);
    if (failures.length == paths.length) return failures;

    // The listing on screen still shows rows that have just left; both views
    // are rebuilt from disk rather than patched in place.
    if (view == AnalyzeView.largeFiles) {
      await showLargeFiles();
    } else {
      _reload(currentPath);
    }
    return failures;
  }

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
