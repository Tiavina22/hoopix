import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/features/purge/domain/entities/purge_activity.dart';
import 'package:hoopix/features/purge/domain/entities/purge_identity_snapshot.dart';
import 'package:hoopix/features/purge/domain/entities/purge_plan.dart';
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

  @override
  Stream<PurgePlan> watchPlan() => Stream.fromIterable(plans);

  @override
  Future<Map<String, String>> approve(List<PurgeCandidate> approved) async {
    approvedCalls.add([for (final c in approved) c.path]);
    return const {};
  }
}

Widget harness(PurgeRepository repository) => MaterialApp(
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
    body: PurgeScreen(repository: repository, homePath: '/Users/tester'),
  ),
);

void main() {
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
