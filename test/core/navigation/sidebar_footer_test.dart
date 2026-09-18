import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/navigation/sidebar_footer.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/l10n/app_localizations.dart';

Widget _harness(Future<String> Function() fetchVersion) => MaterialApp(
  theme: HoopixTheme.light(),
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SidebarFooter(fetchVersion: fetchVersion)),
);

void main() {
  testWidgets('shows the version it is given, not a hand-typed one', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(() async => '9.9.9'));
    await tester.pumpAndSettle();

    expect(find.text('Open source · v9.9.9'), findsOneWidget);
    // The value that used to be typed into the footer by hand.
    expect(find.textContaining('0.1.0'), findsNothing);
  });

  testWidgets('shows nothing while the version is still being read', (
    tester,
  ) async {
    final pending = Future<String>.delayed(
      const Duration(seconds: 1),
      () => '1.0.0',
    );
    await tester.pumpWidget(_harness(() => pending));

    expect(find.textContaining('Open source'), findsNothing);

    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Open source · v1.0.0'), findsOneWidget);
  });

  testWidgets(
    'a version that cannot be read leaves no number, not a wrong one',
    (tester) async {
      await tester.pumpWidget(
        _harness(() async => throw StateError('no plugin')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Open source'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reads the version once, not on every rebuild', (tester) async {
    var reads = 0;
    await tester.pumpWidget(
      _harness(() async {
        reads++;
        return '2.0.0';
      }),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _harness(() async {
        reads++;
        return '2.0.0';
      }),
    );
    await tester.pumpAndSettle();

    expect(reads, 1);
  });
}
