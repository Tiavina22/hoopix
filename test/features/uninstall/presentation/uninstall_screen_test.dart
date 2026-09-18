import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/entities/uninstall_result.dart';
import 'package:hoopix/features/uninstall/domain/repositories/uninstall_inventory_repository.dart';
import 'package:hoopix/features/uninstall/presentation/screens/uninstall_screen.dart';
import 'package:hoopix/l10n/app_localizations.dart';

class _FakeUninstallInventoryRepository
    implements UninstallInventoryRepository {
  _FakeUninstallInventoryRepository(
    this.emissions, {
    this.approveResult,
    this.result,
  });

  final List<List<InstalledApp>> emissions;
  final Map<String, String>? approveResult;

  /// A full result, for tests that need warnings; wins over [approveResult].
  final UninstallResult? result;
  final List<List<String>> approved = [];

  @override
  Stream<List<InstalledApp>> watchInventory() => Stream.fromIterable(emissions);

  @override
  Future<UninstallResult> approve(List<InstalledApp> approved) async {
    this.approved.add([for (final app in approved) app.path]);
    return result ?? UninstallResult(failures: approveResult ?? const {});
  }
}

Widget harness(UninstallInventoryRepository repository) => MaterialApp(
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
    body: UninstallScreen(repository: repository, homePath: '/Users/tester'),
  ),
);

void main() {
  testWidgets(
    'lists installed apps sorted by display name, each one selected by default',
    (tester) async {
      await tester.pumpWidget(
        harness(
          _FakeUninstallInventoryRepository([
            [
              const InstalledApp(
                path: '/Applications/Zed.app',
                bundleId: 'dev.zed.Zed',
                displayName: 'Zed',
              ),
              const InstalledApp(
                path: '/Applications/App.app',
                bundleId: 'com.example.App',
                displayName: 'App',
                sizeBytes: 4096,
              ),
            ],
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // MetricCard renders its title uppercased.
      expect(find.text('APP'), findsOneWidget);
      expect(find.text('ZED'), findsOneWidget);
      // Master checkbox + one per app.
      expect(find.byType(Checkbox), findsNWidgets(3));

      final titles = tester
          .widgetList<Text>(find.textContaining(RegExp(r'^(APP|ZED)$')))
          .map((t) => t.data)
          .toList();
      expect(titles, ['APP', 'ZED']);
    },
  );

  testWidgets('shows a leftover badge only when leftovers were found', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        _FakeUninstallInventoryRepository([
          [
            const InstalledApp(
              path: '/Applications/App.app',
              bundleId: 'com.example.App',
              displayName: 'App',
              leftoverPaths: ['/Users/tester/Library/Caches/App'],
            ),
          ],
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 leftover file'), findsOneWidget);
  });

  testWidgets('flags a shared bundle id install as a shared-install badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        _FakeUninstallInventoryRepository([
          [
            const InstalledApp(
              path: '/Applications/Zed.app',
              bundleId: 'dev.zed.Zed',
              displayName: 'Zed',
            ),
            const InstalledApp(
              path: '/Applications/Zed Nightly.app',
              bundleId: 'dev.zed.Zed',
              displayName: 'Zed Nightly',
            ),
          ],
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shared install'), findsNWidgets(2));
  });

  testWidgets('shows the nothing-found state for an empty inventory', (
    tester,
  ) async {
    await tester.pumpWidget(harness(_FakeUninstallInventoryRepository([[]])));
    await tester.pumpAndSettle();

    expect(find.text('No apps found.'), findsOneWidget);
  });

  testWidgets('the button is disabled when there is nothing to do', (
    tester,
  ) async {
    await tester.pumpWidget(harness(_FakeUninstallInventoryRepository([[]])));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('nothing moves until the confirmation is accepted', (
    tester,
  ) async {
    final repository = _FakeUninstallInventoryRepository([
      [
        const InstalledApp(
          path: '/Applications/App.app',
          bundleId: 'com.example.App',
          displayName: 'App',
          sizeBytes: 4 * 1024 * 1024,
        ),
      ],
    ]);

    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Uninstall'));
    await tester.pumpAndSettle();

    expect(find.text('Uninstall 1 app?'), findsOneWidget);
    expect(find.textContaining('Frees 4.0 MB'), findsOneWidget);
    expect(repository.approved, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repository.approved, isEmpty);
  });

  testWidgets('tags an app Homebrew manages', (tester) async {
    await tester.pumpWidget(
      harness(
        _FakeUninstallInventoryRepository([
          [
            const InstalledApp(
              path: '/Applications/Firefox.app',
              bundleId: 'org.mozilla.firefox',
              displayName: 'Firefox',
              caskName: 'firefox',
            ),
            const InstalledApp(
              path: '/Applications/App.app',
              bundleId: 'com.example.App',
              displayName: 'App',
            ),
          ],
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Homebrew'), findsOneWidget);
  });

  testWidgets(
    'warns that a Homebrew uninstall is permanent only when one is selected',
    (tester) async {
      final repository = _FakeUninstallInventoryRepository([
        [
          const InstalledApp(
            path: '/Applications/Firefox.app',
            bundleId: 'org.mozilla.firefox',
            displayName: 'Firefox',
            caskName: 'firefox',
          ),
          const InstalledApp(
            path: '/Applications/App.app',
            bundleId: 'com.example.App',
            displayName: 'App',
          ),
        ],
      ]);
      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Uninstall'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('1 of them is managed by Homebrew'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Uncheck Firefox (sorted after App): the warning must go with it.
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Uninstall'));
      await tester.pumpAndSettle();
      expect(find.textContaining('managed by Homebrew'), findsNothing);
    },
  );

  testWidgets(
    'after removal, says what macOS still keeps and where to turn it off',
    (tester) async {
      final repository = _FakeUninstallInventoryRepository(
        [
          [
            const InstalledApp(
              path: '/Applications/AdGuard.app',
              bundleId: 'com.adguard.mac.adguard',
              displayName: 'AdGuard',
            ),
          ],
        ],
        result: const UninstallResult(
          backgroundItemApps: ['AdGuard'],
          systemExtensionApps: ['AdGuard'],
        ),
      );
      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Uninstall'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Uninstall'));
      await tester.pumpAndSettle();

      expect(find.text('Still active after removal'), findsOneWidget);
      expect(
        find.textContaining('A background item is still running for AdGuard'),
        findsOneWidget,
      );
      expect(
        find.textContaining('System extensions may remain for AdGuard'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
      expect(find.text('Still active after removal'), findsNothing);
    },
  );

  testWidgets('a clean removal shows no warning at all', (tester) async {
    final repository = _FakeUninstallInventoryRepository([
      [
        const InstalledApp(
          path: '/Applications/App.app',
          bundleId: 'com.example.App',
          displayName: 'App',
        ),
      ],
    ]);
    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Uninstall'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Uninstall'));
    await tester.pumpAndSettle();

    expect(find.text('Still active after removal'), findsNothing);
    expect(find.text('Uninstalled 1 app.'), findsOneWidget);
  });

  testWidgets('confirming uninstalls exactly what was selected', (
    tester,
  ) async {
    final repository = _FakeUninstallInventoryRepository([
      [
        const InstalledApp(
          path: '/Applications/App.app',
          bundleId: 'com.example.App',
          displayName: 'App',
          sizeBytes: 10,
        ),
      ],
    ]);

    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Uninstall'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Uninstall'));
    await tester.pumpAndSettle();

    expect(repository.approved.single, ['/Applications/App.app']);
    expect(find.text('Uninstalled 1 app.'), findsOneWidget);
  });

  testWidgets('surfaces a refusal reported by the repository', (
    tester,
  ) async {
    final repository = _FakeUninstallInventoryRepository(
      [
        [
          const InstalledApp(
            path: '/Applications/App.app',
            bundleId: 'com.example.App',
            displayName: 'App',
          ),
        ],
      ],
      approveResult: {'/Applications/App.app': 'still running'},
    );

    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Uninstall'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Uninstall'));
    await tester.pumpAndSettle();

    expect(find.text('1 item could not be removed.'), findsOneWidget);
  });

  group('selection', () {
    List<InstalledApp> twoApps() => const [
      InstalledApp(
        path: '/Applications/App-one.app',
        bundleId: 'com.example.One',
        displayName: 'App-one',
        sizeBytes: 1024,
      ),
      InstalledApp(
        path: '/Applications/App-two.app',
        bundleId: 'com.example.Two',
        displayName: 'App-two',
        sizeBytes: 2048,
      ),
    ];

    testWidgets(
      'unchecking one app excludes only that path from the approval',
      (tester) async {
        final repository = _FakeUninstallInventoryRepository([twoApps()]);
        await tester.pumpWidget(harness(repository));
        await tester.pumpAndSettle();

        // Checkbox order: master, App-one, App-two.
        await tester.tap(find.byType(Checkbox).at(1));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Uninstall'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Uninstall'));
        await tester.pumpAndSettle();

        expect(repository.approved.single, [
          '/Applications/App-two.app',
        ]);
      },
    );

    testWidgets(
      'unchecking the master checkbox excludes everything, checking it '
      'again restores it all',
      (tester) async {
        final repository = _FakeUninstallInventoryRepository([twoApps()]);
        await tester.pumpWidget(harness(repository));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();

        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(find.text('Nothing selected'), findsOneWidget);

        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Uninstall'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Uninstall'));
        await tester.pumpAndSettle();

        expect(repository.approved.single, [
          '/Applications/App-one.app',
          '/Applications/App-two.app',
        ]);
      },
    );

    testWidgets('the header count reflects the selection, not the inventory', (
      tester,
    ) async {
      final repository = _FakeUninstallInventoryRepository([twoApps()]);
      await tester.pumpWidget(harness(repository));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 apps'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 app'), findsOneWidget);
      expect(find.textContaining('2 apps'), findsNothing);
    });
  });
}
