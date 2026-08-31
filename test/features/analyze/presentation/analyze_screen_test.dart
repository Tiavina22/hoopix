import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';
import 'package:hoopix/features/analyze/domain/repositories/analyze_repository.dart';
import 'package:hoopix/features/analyze/presentation/screens/analyze_screen.dart';
import 'package:hoopix/l10n/app_localizations.dart';

const _home = '/Users/tester';

class _FakeAnalyzeRepository implements AnalyzeRepository {
  _FakeAnalyzeRepository(this._scans, {this.largeFiles = const []});

  final List<List<String>> trashed = [];

  @override
  Future<Map<String, String>> moveToTrash(List<String> paths) async {
    trashed.add(paths);
    return const {};
  }

  final Map<String, DirectoryScan> _scans;
  final List<AnalyzeEntry> largeFiles;
  final List<String> watched = [];
  final List<String> searched = [];
  final List<String> revealed = [];

  @override
  Stream<DirectoryScan> watchOverview() => watchDirectory(overviewPath);

  @override
  Future<List<AnalyzeEntry>> findLargeFiles(String root) async {
    searched.add(root);
    return largeFiles;
  }

  @override
  Stream<DirectoryScan> watchDirectory(String path) {
    watched.add(path);
    return Stream.value(
      _scans[path] ??
          DirectoryScan(path: path, status: DirectoryScanStatus.loaded),
    );
  }

  int? snapshotCount = 0;

  @override
  Future<int?> localSnapshotCount() async => snapshotCount;

  @override
  Future<bool> revealInFinder(String path) async {
    revealed.add(path);
    return true;
  }
}

/// The curated overview, as the real datasource would produce it.
DirectoryScan _overviewScan() => const DirectoryScan(
  path: overviewPath,
  status: DirectoryScanStatus.loaded,
  entries: [
    AnalyzeEntry(
      path: '$_home/Library',
      name: 'User Library',
      isDirectory: true,
      sizeBytes: 40 * 1024 * 1024,
      overviewKind: OverviewRowKind.userLibrary,
    ),
    AnalyzeEntry(
      path: '$_home/Library/Caches/Homebrew',
      name: 'Homebrew Cache',
      isDirectory: true,
      sizeBytes: 2048,
      overviewKind: OverviewRowKind.tool,
    ),
  ],
  totalBytes: 40 * 1024 * 1024 + 2048,
);

Widget _harness(AnalyzeRepository repository, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    theme: HoopixTheme.light(),
    // Pinned so text assertions don't depend on the host/CI locale.
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: AnalyzeScreen(repository: repository, homePath: _home),
    ),
  );
}

/// Row actions only appear under the pointer, so a test that wants to press
/// one has to hover the row first, the way a user does.
Future<void> _hoverRow(WidgetTester tester, String label) async {
  final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await pointer.addPointer(location: Offset.zero);
  addTearDown(pointer.removePointer);
  await pointer.moveTo(tester.getCenter(find.text(label)));
  await tester.pump();
}

void main() {
  testWidgets('opens on the curated overview, not a directory', (tester) async {
    final repository = _FakeAnalyzeRepository({overviewPath: _overviewScan()});

    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    expect(repository.watched, [overviewPath]);
    expect(find.text('Overview'), findsOneWidget); // breadcrumb root
    expect(find.text('User Library'), findsOneWidget);
    // Tool rows keep their product name rather than being translated.
    expect(find.text('Homebrew Cache'), findsOneWidget);
  });

  testWidgets('translates curated row names but not product names', (
    tester,
  ) async {
    final repository = _FakeAnalyzeRepository({overviewPath: _overviewScan()});

    await tester.pumpWidget(_harness(repository, locale: const Locale('fr')));
    await tester.pump();

    expect(find.text('Bibliothèque utilisateur'), findsOneWidget);
    expect(find.text('Homebrew Cache'), findsOneWidget);
  });

  testWidgets('drilling into an overview row explores that path', (
    tester,
  ) async {
    final repository = _FakeAnalyzeRepository({
      overviewPath: _overviewScan(),
      '$_home/Library': const DirectoryScan(
        path: '$_home/Library',
        status: DirectoryScanStatus.loaded,
        entries: [
          AnalyzeEntry(
            path: '$_home/Library/Caches',
            name: 'Caches',
            isDirectory: true,
            sizeBytes: 1024,
          ),
        ],
        totalBytes: 1024,
      ),
    });

    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    await tester.tap(find.text('User Library'));
    await tester.pump();

    expect(repository.watched, [overviewPath, '$_home/Library']);
    expect(find.text('Caches'), findsOneWidget);
    // The trail keeps the row's curated name, not the folder name "Library".
    expect(find.text('User Library'), findsOneWidget);
  });


  testWidgets('a truncated directory shows the true count and a note', (
    tester,
  ) async {
    final repository = _FakeAnalyzeRepository({
      overviewPath: _overviewScan(),
      '$_home/Library': DirectoryScan(
        path: '$_home/Library',
        status: DirectoryScanStatus.loaded,
        totalEntryCount: 340,
        totalBytes: 900,
        entries: [
          for (var i = 0; i < 30; i++)
            AnalyzeEntry(
              path: '$_home/Library/f\$i',
              name: 'f\$i',
              isDirectory: false,
              sizeBytes: 30 - i,
            ),
        ],
      ),
    });

    await tester.pumpWidget(_harness(repository));
    await tester.pump();
    await tester.tap(find.text('User Library'));
    await tester.pump();

    // The header count is the true count, not the 30 rows on screen.
    expect(find.textContaining('340 items'), findsOneWidget);
    expect(find.text('Showing the 30 largest of 340.'), findsOneWidget);
  });

  testWidgets('an untruncated directory shows no note', (tester) async {
    final repository = _FakeAnalyzeRepository({
      overviewPath: _overviewScan(),
      '$_home/Library': const DirectoryScan(
        path: '$_home/Library',
        status: DirectoryScanStatus.loaded,
        entries: [
          AnalyzeEntry(
            path: '$_home/Library/one',
            name: 'one',
            isDirectory: false,
            sizeBytes: 10,
          ),
        ],
        totalBytes: 10,
      ),
    });

    await tester.pumpWidget(_harness(repository));
    await tester.pump();
    await tester.tap(find.text('User Library'));
    await tester.pump();

    expect(find.textContaining('Showing the'), findsNothing);
  });


  testWidgets('shows the local snapshot note only when there are some', (
    tester,
  ) async {
    final repository = _FakeAnalyzeRepository({overviewPath: _overviewScan()})
      ..snapshotCount = 4;

    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    expect(
      find.textContaining('4 Time Machine local snapshots'),
      findsOneWidget,
    );
  });

  testWidgets('says nothing about snapshots when there are none', (
    tester,
  ) async {
    final repository = _FakeAnalyzeRepository({overviewPath: _overviewScan()})
      ..snapshotCount = 0;

    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    expect(find.textContaining('Time Machine'), findsNothing);
  });

  testWidgets('the snapshot note only appears on the overview', (
    tester,
  ) async {
    final repository = _FakeAnalyzeRepository({
      overviewPath: _overviewScan(),
      '$_home/Library': const DirectoryScan(
        path: '$_home/Library',
        status: DirectoryScanStatus.loaded,
      ),
    })..snapshotCount = 4;

    await tester.pumpWidget(_harness(repository));
    await tester.pump();
    await tester.tap(find.text('User Library'));
    await tester.pump();

    expect(find.textContaining('Time Machine'), findsNothing);
  });

  testWidgets('the overview breadcrumb returns to the overview', (
    tester,
  ) async {
    final repository = _FakeAnalyzeRepository({
      overviewPath: _overviewScan(),
      '$_home/Library': const DirectoryScan(
        path: '$_home/Library',
        status: DirectoryScanStatus.loaded,
      ),
    });

    await tester.pumpWidget(_harness(repository));
    await tester.pump();
    await tester.tap(find.text('User Library'));
    await tester.pump();

    await tester.tap(find.text('Overview'));
    await tester.pump();

    expect(repository.watched, [overviewPath, '$_home/Library', overviewPath]);
  });

  testWidgets('tapping a file does not navigate', (tester) async {
    final repository = _FakeAnalyzeRepository({
      overviewPath: const DirectoryScan(
        path: overviewPath,
        status: DirectoryScanStatus.loaded,
        entries: [
          AnalyzeEntry(
            path: '$_home/notes.txt',
            name: 'notes.txt',
            isDirectory: false,
            sizeBytes: 2048,
          ),
        ],
        totalBytes: 2048,
      ),
    });

    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    await tester.tap(find.text('notes.txt'));
    await tester.pump();

    expect(repository.watched, [overviewPath]);
  });

  testWidgets('an unreadable directory says so instead of looking empty', (
    tester,
  ) async {
    final repository = _FakeAnalyzeRepository({
      overviewPath: const DirectoryScan(
        path: overviewPath,
        status: DirectoryScanStatus.permissionDenied,
      ),
    });

    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    expect(find.text("hoopix can't read this folder."), findsOneWidget);
  });

  testWidgets('the largest-files toggle shows Spotlight results', (
    tester,
  ) async {
    final repository = _FakeAnalyzeRepository(
      {overviewPath: _overviewScan()},
      largeFiles: const [
        AnalyzeEntry(
          path: '$_home/Movies/raw.mov',
          name: 'raw.mov',
          isDirectory: false,
          sizeBytes: 4 * 1024 * 1024 * 1024,
        ),
      ],
    );

    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    await tester.tap(find.text('Largest files'));
    await tester.pumpAndSettle();

    // Searched from home, because the overview is not itself a directory.
    expect(repository.searched, [_home]);
    expect(find.text('raw.mov'), findsOneWidget);
    expect(find.text('User Library'), findsNothing);
  });

  testWidgets('says so when Spotlight finds no large files', (tester) async {
    final repository = _FakeAnalyzeRepository({overviewPath: _overviewScan()});

    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    await tester.tap(find.text('Largest files'));
    await tester.pumpAndSettle();

    expect(find.text('No files over 100 MB here.'), findsOneWidget);
  });

  testWidgets('nothing is trashed until the confirmation is accepted', (
    tester,
  ) async {
    final repository = _FakeAnalyzeRepository({overviewPath: _overviewScan()});

    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    await _hoverRow(tester, 'User Library');
    await tester.tap(find.byTooltip('Move to Trash').first);
    await tester.pumpAndSettle();

    // The dialog names the item and says where it goes.
    expect(find.text('Move “User Library” to the Trash?'), findsOneWidget);
    expect(repository.trashed, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.trashed, isEmpty);
  });

  testWidgets('confirming moves the entry to the Trash', (tester) async {
    final repository = _FakeAnalyzeRepository({overviewPath: _overviewScan()});

    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    await _hoverRow(tester, 'User Library');
    await tester.tap(find.byTooltip('Move to Trash').first);
    await tester.pumpAndSettle();
    // The confirm button, not the dialog title.
    await tester.tap(find.widgetWithText(TextButton, 'Move to Trash'));
    await tester.pumpAndSettle();

    expect(repository.trashed, [
      ['$_home/Library'],
    ]);
  });

  testWidgets('the filter narrows the visible rows', (tester) async {
    final repository = _FakeAnalyzeRepository({overviewPath: _overviewScan()});

    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'homebrew');
    await tester.pump();

    expect(find.text('Homebrew Cache'), findsOneWidget);
    expect(find.text('User Library'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pump();

    expect(find.text('Nothing matches that filter.'), findsOneWidget);
  });


  testWidgets('copy as JSON puts the current listing on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final repository = _FakeAnalyzeRepository({overviewPath: _overviewScan()});
    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Copy as JSON'));
    await tester.pump();

    expect(copied, isNotNull);
    expect(copied, contains('"path"'));
    expect(copied, contains('"User Library"'));
    expect(find.text('Copied as JSON.'), findsOneWidget);
  });

  testWidgets('an empty directory says so', (tester) async {
    final repository = _FakeAnalyzeRepository(const {});

    await tester.pumpWidget(_harness(repository));
    await tester.pump();

    expect(find.text('This folder is empty.'), findsOneWidget);
  });
}
