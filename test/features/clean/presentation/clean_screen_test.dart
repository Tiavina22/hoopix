import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/repositories/clean_repository.dart';
import 'package:hoopix/features/clean/presentation/screens/clean_screen.dart';
import 'package:hoopix/l10n/app_localizations.dart';

class _FakeCleanRepository implements CleanRepository {
  _FakeCleanRepository(this.plans);

  final List<CleanPlan> plans;
  final List<List<String>> approved = [];

  @override
  Stream<CleanPlan> watchPlan() => Stream.fromIterable(plans);

  @override
  Future<Map<String, String>> approve(List<CleanCandidate> candidates) async {
    approved.add([for (final c in candidates) c.path]);
    return const {};
  }
}

Widget harness(CleanRepository repository) => MaterialApp(
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
    body: CleanScreen(repository: repository, homePath: '/Users/tester'),
  ),
);

void main() {
  testWidgets('says plainly that a preview removes nothing', (tester) async {
    await tester.pumpWidget(
      harness(
        _FakeCleanRepository([
          const CleanPlan(
            candidates: [
              CleanCandidate(
                path: '/a/cache',
                section: 'User essentials',
                sizeBytes: 2048,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This is a preview. Nothing is removed until you say so.'),
      findsOneWidget,
    );
  });

  testWidgets('groups what would go by section, with its total', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        _FakeCleanRepository([
          const CleanPlan(
            candidates: [
              CleanCandidate(
                path: '/Users/tester/Library/Caches/app-one',
                section: 'User essentials',
                sizeBytes: 1024 * 1024,
              ),
              CleanCandidate(
                path: '/Users/tester/Library/Logs/app-two',
                section: 'User essentials',
                sizeBytes: 1024 * 1024,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('USER ESSENTIALS'),
      findsOneWidget,
    ); // card titles uppercase
    expect(find.text('app-one'), findsOneWidget);
    expect(find.text('app-two'), findsOneWidget);
    expect(find.textContaining('2 items'), findsOneWidget);
  });

  testWidgets('says what it left alone, and why', (tester) async {
    await tester.pumpWidget(
      harness(
        _FakeCleanRepository([
          const CleanPlan(
            candidates: [
              CleanCandidate(
                path: '/a/cache',
                section: 'User essentials',
                sizeBytes: 10,
              ),
              CleanCandidate(
                path: '/a/keychain',
                section: 'User essentials',
                skipReason: CleanSkipReason.protected,
              ),
              CleanCandidate(
                path: '/a/mine',
                section: 'User essentials',
                skipReason: CleanSkipReason.whitelisted,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    // A cleanup tool that quietly skips things is one you cannot check.
    expect(find.text('LEFT ALONE'), findsOneWidget);
    expect(find.text('Protected'), findsOneWidget);
    expect(find.text('On your whitelist'), findsOneWidget);
  });

  testWidgets('a plan with nothing eligible says so', (tester) async {
    await tester.pumpWidget(
      harness(_FakeCleanRepository([const CleanPlan(candidates: [])])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing to clean up right now.'), findsOneWidget);
  });

  testWidgets('sizes landing later update the totals in place', (tester) async {
    await tester.pumpWidget(
      harness(
        _FakeCleanRepository([
          // First frame: named but unmeasured.
          const CleanPlan(
            candidates: [
              CleanCandidate(path: '/a/cache', section: 'User essentials'),
            ],
          ),
          const CleanPlan(
            candidates: [
              CleanCandidate(
                path: '/a/cache',
                section: 'User essentials',
                sizeBytes: 5 * 1024 * 1024,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('5.0 MB'), findsWidgets);
  });

  testWidgets('nothing moves until the confirmation is accepted', (
    tester,
  ) async {
    final repository = _FakeCleanRepository([
      const CleanPlan(
        candidates: [
          CleanCandidate(
            path: '/Users/tester/Library/Caches/app',
            section: 'User essentials',
            sizeBytes: 4 * 1024 * 1024,
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Move to Trash'));
    await tester.pumpAndSettle();

    // The dialog says how much, and where it goes.
    expect(find.text('Move 1 item to the Trash?'), findsOneWidget);
    expect(find.textContaining('Frees 4.0 MB'), findsOneWidget);
    expect(repository.approved, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repository.approved, isEmpty);
  });

  testWidgets('confirming moves exactly what the plan proposed', (
    tester,
  ) async {
    final repository = _FakeCleanRepository([
      const CleanPlan(
        candidates: [
          CleanCandidate(
            path: '/Users/tester/Library/Caches/app',
            section: 'User essentials',
            sizeBytes: 10,
          ),
          CleanCandidate(
            path: '/Users/tester/Library/Keychains/login',
            section: 'User essentials',
            skipReason: CleanSkipReason.protected,
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Move to Trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Move to Trash'));
    await tester.pumpAndSettle();

    // Only the eligible path; the protected one was never offered.
    expect(repository.approved.single, ['/Users/tester/Library/Caches/app']);
  });

  testWidgets('a batch with an owner-command candidate gets honest copy', (
    tester,
  ) async {
    final repository = _FakeCleanRepository([
      const CleanPlan(
        candidates: [
          CleanCandidate(
            path: '/Users/tester/.npm',
            section: 'Developer tools',
            sizeBytes: 4 * 1024 * 1024,
            ownerCommand: ['npm', 'cache', 'clean', '--force'],
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();

    // Neither the button nor the dialog claims Trash recoverability.
    expect(find.widgetWithText(FilledButton, 'Clean Up'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clean Up'));
    await tester.pumpAndSettle();

    expect(find.text('Clean up 1 item?'), findsOneWidget);
    expect(find.textContaining("can’t be put back"), findsOneWidget);
    expect(find.textContaining('Move to Trash'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Clean Up'));
    await tester.pumpAndSettle();

    expect(repository.approved.single, ['/Users/tester/.npm']);
    expect(find.text('Cleaned up 1 item.'), findsOneWidget);
  });

  testWidgets(
    'a batch with a privileged-deletion candidate gets the same honest copy',
    (tester) async {
      final repository = _FakeCleanRepository([
        const CleanPlan(
          candidates: [
            CleanCandidate(
              path: '/Library/Caches/com.apple.iconservices.store',
              section: 'System',
              sizeBytes: 2 * 1024 * 1024,
              requiresPrivilegedDeletion: true,
            ),
          ],
        ),
      ]);

      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Clean Up'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Clean Up'));
      await tester.pumpAndSettle();

      expect(find.text('Clean up 1 item?'), findsOneWidget);
      expect(find.textContaining("can’t be put back"), findsOneWidget);
      expect(find.textContaining('Move to Trash'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Clean Up'));
      await tester.pumpAndSettle();

      expect(repository.approved.single, [
        '/Library/Caches/com.apple.iconservices.store',
      ]);
      expect(find.text('Cleaned up 1 item.'), findsOneWidget);
    },
  );

  testWidgets('the button is disabled when there is nothing to do', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(_FakeCleanRepository([const CleanPlan(candidates: [])])),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
