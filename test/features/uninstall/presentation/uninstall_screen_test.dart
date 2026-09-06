import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/repositories/uninstall_inventory_repository.dart';
import 'package:hoopix/features/uninstall/presentation/screens/uninstall_screen.dart';
import 'package:hoopix/l10n/app_localizations.dart';

class _FakeUninstallInventoryRepository
    implements UninstallInventoryRepository {
  _FakeUninstallInventoryRepository(this.emissions);

  final List<List<InstalledApp>> emissions;

  @override
  Stream<List<InstalledApp>> watchInventory() => Stream.fromIterable(emissions);
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
    'lists installed apps sorted by display name, no delete control',
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
      expect(find.byType(Checkbox), findsNothing);
      expect(
        find.textContaining('nothing here removes an app yet'),
        findsOneWidget,
      );

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
}
