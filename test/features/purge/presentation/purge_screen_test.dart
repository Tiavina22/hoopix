import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/features/purge/domain/entities/purge_activity.dart';
import 'package:hoopix/features/purge/domain/entities/purge_identity_snapshot.dart';
import 'package:hoopix/features/purge/domain/entities/purge_plan.dart';
import 'package:hoopix/features/purge/domain/repositories/purge_paths_repository.dart';
import 'package:hoopix/features/purge/domain/repositories/purge_repository.dart';
import 'package:hoopix/features/purge/presentation/screens/purge_screen.dart';
import 'package:hoopix/l10n/app_localizations.dart';

const _identity = PurgeIdentitySnapshot(
  parentIdentity: '1:1',
  targetIdentity: '1:2',
);

class _FakePurgeRepository implements PurgeRepository {
  _FakePurgeRepository(this.plans);

  final List<PurgePlan> plans;
  final List<List<String>> approvedCalls = [];
  var watchCount = 0;

  @override
  Stream<PurgePlan> watchPlan() {
    watchCount++;
    return Stream.fromIterable(plans);
  }

  @override
  Future<Map<String, String>> approve(List<PurgeCandidate> approved) async {
    approvedCalls.add([for (final c in approved) c.path]);
    return const {};
  }
}

class _FakePathsRepository implements PurgePathsRepository {
  _FakePathsRepository(this.lines, this.discovered);

  List<String>? lines;
  final List<String> discovered;
  final saves = <List<String>>[];

  @override
  String get displayPath => '~/.config/hoopix/purge_paths';

  @override
  Future<List<String>?> read() async => lines;

  @override
  Future<void> save(List<String> lines) async {
    saves.add(lines);
    this.lines = lines;
  }

  @override
  Future<List<String>> discover() async => discovered;

  @override
  bool folderExists(String path) => path != '/Users/tester/Gone';
}

Widget harness(
  PurgeRepository repository, {
  PurgePathsRepository? paths,
}) => MaterialApp(
  theme: HoopixTheme.light(),
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: PurgeScreen(
      repository: repository,
      pathsRepository: paths,
      homePath: '/Users/tester',
    ),
  ),
);

void main() {
  testWidgets('the folders editor saves the user list, then scans again', (
    tester,
  ) async {
    final repository = _FakePurgeRepository([const PurgePlan(candidates: [])]);
    final paths = _FakePathsRepository(null, ['/Users/tester/Code']);
    await tester.pumpWidget(harness(repository, paths: paths));
    await tester.pumpAndSettle();
    expect(repository.watchCount, 1);

    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
    expect(find.text('~/Code'), findsOneWidget);
    expect(find.textContaining('Automatic:'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '/');
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(
      find.text('Scanning the whole disk is not allowed.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '~/Gone');
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text('~/Gone'), findsOneWidget);
    expect(find.text('not found'), findsOneWidget);
    expect(find.textContaining('Your own list'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      paths.saves.single.where((l) => !l.startsWith('#') && l.isNotEmpty),
      ['~/Code', '~/Gone'],
    );
    expect(repository.watchCount, 2);
  });

  testWidgets('going back to automatic saves no folder', (tester) async {
    final repository = _FakePurgeRepository([const PurgePlan(candidates: [])]);
    final paths = _FakePathsRepository(['~/Work'], ['/Users/tester/Code']);
    await tester.pumpWidget(harness(repository, paths: paths));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
    expect(find.text('~/Work'), findsOneWidget);

    await tester.tap(find.text('Use automatic discovery'));
    await tester.pump();
    expect(find.text('~/Code'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      paths.saves.single.where((l) => !l.startsWith('#') && l.isNotEmpty),
      isEmpty,
    );
  });

  testWidgets('says plainly that removal here is permanent', (tester) async {
    await tester.pumpWidget(
      harness(
        _FakePurgeRepository([
          const PurgePlan(
            candidates: [
              PurgeCandidate(
                path: '/repo/node_modules',
                searchRoot: '/repo',
                activity: PurgeActivityState.old,
                isCloudSynced: false,
                identityAtScan: _identity,
                sizeBytes: 2048,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Deleted permanently, not through the Trash'),
      findsOneWidget,
    );
    expect(find.text('node_modules'), findsOneWidget);
  });

  testWidgets('a recent candidate shows unchecked with its badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        _FakePurgeRepository([
          const PurgePlan(
            candidates: [
              PurgeCandidate(
                path: '/repo/node_modules',
                searchRoot: '/repo',
                activity: PurgeActivityState.recent,
                isCloudSynced: false,
                identityAtScan: _identity,
                sizeBytes: 2048,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recently touched'), findsOneWidget);
    expect(find.text('Nothing selected'), findsOneWidget);

    final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(checkboxes.map((c) => c.value), everyElement(isFalse));
  });

  testWidgets('confirming deletes only the selected candidates', (
    tester,
  ) async {
    final repository = _FakePurgeRepository([
      const PurgePlan(
        candidates: [
          PurgeCandidate(
            path: '/repo/node_modules',
            searchRoot: '/repo',
            activity: PurgeActivityState.old,
            isCloudSynced: false,
            identityAtScan: _identity,
            sizeBytes: 2048,
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete Permanently'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('This cannot be undone'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete Permanently'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.approvedCalls.single, ['/repo/node_modules']);
  });

  testWidgets('shows the nothing-to-do state when the plan is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(_FakePurgeRepository([const PurgePlan(candidates: [])])),
    );
    await tester.pumpAndSettle();

    expect(find.text('No old project artifacts to clean.'), findsOneWidget);
  });
}
