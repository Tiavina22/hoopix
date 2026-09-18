import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/features/about/presentation/widgets/about_dialog.dart';
import 'package:hoopix/l10n/app_localizations.dart';

Widget _harness({
  required List<Uri> opened,
  Future<String> Function()? fetchVersion,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  theme: HoopixTheme.light(),
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => HoopixAboutDialog(
            fetchVersion: fetchVersion ?? () async => '1.2.3',
            // Never a real browser: the link is only recorded.
            openUrl: (url) async => opened.add(url),
          ),
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the name, tagline, version, license and copyright', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(opened: []));
    await _open(tester);

    expect(find.text('Hoopix'), findsOneWidget);
    expect(
      find.text('Free, open-source macOS cleanup and system-health app.'),
      findsOneWidget,
    );
    expect(find.text('Version 1.2.3'), findsOneWidget);
    expect(find.text('Licensed under the GNU GPLv3'), findsOneWidget);
    expect(
      find.text('© ${DateTime.now().year} Tiavina Ramilison'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the creator avatar opens the creator GitHub profile', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(_harness(opened: opened));
    await _open(tester);

    await tester.tap(find.text('Created by Tiavina'));
    await tester.pump();

    expect(opened, [Uri.parse('https://github.com/Tiavina22')]);
  });

  testWidgets('a contributor avatar opens that contributor GitHub profile', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(_harness(opened: opened));
    await _open(tester);

    expect(find.text('Contributors'), findsOneWidget);
    // The name under the one contributor avatar, not the "Created by" row.
    await tester.tap(find.text('Tiavina'));
    await tester.pump();

    expect(opened, [Uri.parse('https://github.com/Tiavina22')]);
  });

  testWidgets('the license link opens the LICENSE file on GitHub', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(_harness(opened: opened));
    await _open(tester);

    await tester.tap(find.text('Licensed under the GNU GPLv3'));
    await tester.pump();

    expect(opened, [
      Uri.parse('https://github.com/Tiavina22/hoopix/blob/main/LICENSE'),
    ]);
  });

  testWidgets('renders both circular avatars', (tester) async {
    await tester.pumpWidget(_harness(opened: []));
    await _open(tester);

    expect(find.byType(ClipOval), findsNWidgets(2));
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('a version lookup that fails leaves the rest of the dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(opened: [], fetchVersion: () async => throw StateError('no')),
    );
    await _open(tester);

    expect(find.textContaining('Version'), findsNothing);
    expect(find.text('Hoopix'), findsOneWidget);
    expect(find.text('Licensed under the GNU GPLv3'), findsOneWidget);
  });

  testWidgets('Close dismisses the dialog', (tester) async {
    await tester.pumpWidget(_harness(opened: []));
    await _open(tester);
    expect(find.byType(HoopixAboutDialog), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(HoopixAboutDialog), findsNothing);
  });

  testWidgets('speaks French when the app locale is French', (tester) async {
    await tester.pumpWidget(_harness(opened: [], locale: const Locale('fr')));
    await _open(tester);

    expect(find.text('Créé par Tiavina'), findsOneWidget);
    expect(find.text('Contributeurs'), findsOneWidget);
    expect(find.text('Sous licence GNU GPLv3'), findsOneWidget);
    expect(find.text('Fermer'), findsOneWidget);
  });
}
