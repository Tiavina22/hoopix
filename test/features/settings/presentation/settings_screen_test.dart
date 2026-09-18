import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/locale/locale_controller.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/theme_controller.dart';
import 'package:hoopix/features/about/presentation/widgets/about_dialog.dart';
import 'package:hoopix/features/settings/presentation/screens/settings_screen.dart';
import 'package:hoopix/l10n/app_localizations.dart';

// Only ever read from: no test here calls a setter, so nothing is written to
// this machine's real hoopix preferences.
Widget _harness() => MaterialApp(
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
    body: SettingsScreen(
      themeController: ThemeController(),
      localeController: LocaleController(),
    ),
  ),
);

void main() {
  testWidgets('has an About card that opens the Hoopix About dialog', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.byType(HoopixAboutDialog), findsNothing);
    await tester.tap(find.text('About Hoopix'));
    await tester.pumpAndSettle();

    expect(find.byType(HoopixAboutDialog), findsOneWidget);
    expect(find.text('Contributors'), findsOneWidget);
  });
}
