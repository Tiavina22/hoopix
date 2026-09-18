import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/features/about/presentation/widgets/about_dialog.dart';
import 'package:hoopix/features/about/presentation/widgets/about_menu_listener.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// What the native side does when the app menu's About item is clicked:
/// `aboutChannel.invokeMethod("show")`, delivered to Dart as a platform
/// message on [aboutMenuChannelName].
Future<void> _menuClick(String method) async {
  const codec = StandardMethodCodec();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        aboutMenuChannelName,
        codec.encodeMethodCall(MethodCall(method)),
        (_) {},
      );
}

Widget _app(GlobalKey<NavigatorState> key) => AboutMenuListener(
  navigatorKey: key,
  // Version lookup and links stubbed: no platform channel, no browser.
  dialogBuilder: (_) => HoopixAboutDialog(
    fetchVersion: () async => '9.9.9',
    openUrl: (_) async {},
  ),
  child: MaterialApp(
    navigatorKey: key,
    theme: HoopixTheme.light(),
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: Text('app body')),
  ),
);

void main() {
  testWidgets('the native About menu click opens the About dialog', (
    tester,
  ) async {
    await tester.pumpWidget(_app(GlobalKey<NavigatorState>()));
    expect(find.byType(HoopixAboutDialog), findsNothing);

    await _menuClick('show');
    await tester.pumpAndSettle();

    expect(find.byType(HoopixAboutDialog), findsOneWidget);
    expect(find.text('Version 9.9.9'), findsOneWidget);
  });

  testWidgets('a method it does not know opens nothing', (tester) async {
    await tester.pumpWidget(_app(GlobalKey<NavigatorState>()));

    await _menuClick('somethingElse');
    await tester.pumpAndSettle();

    expect(find.byType(HoopixAboutDialog), findsNothing);
  });

  testWidgets('a click before any Navigator exists is dropped, not a crash', (
    tester,
  ) async {
    // A key attached to nothing: currentContext is null, as it is before the
    // first frame has built the MaterialApp.
    await tester.pumpWidget(
      AboutMenuListener(
        navigatorKey: GlobalKey<NavigatorState>(),
        child: const SizedBox(),
      ),
    );

    await _menuClick('show');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('stops listening once removed from the tree', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key));
    await tester.pumpWidget(const SizedBox());

    await _menuClick('show');
    await tester.pumpAndSettle();

    expect(find.byType(HoopixAboutDialog), findsNothing);
  });

  // The native half can't run under `flutter test`, so this pins the three
  // strings that have to agree for the menu click to reach Dart: the XIB
  // action, the Swift responder method, and the channel name. Renaming any
  // one of them silently breaks the About menu item.
  test('the native menu wiring agrees with the Dart channel', () {
    final swift = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final xib = File('macos/Runner/Base.lproj/MainMenu.xib').readAsStringSync();

    expect(swift, contains('"$aboutMenuChannelName"'));
    expect(swift, contains('@objc func showAboutPanel('));
    expect(swift, contains('invokeMethod("show"'));
    expect(xib, contains('selector="showAboutPanel:"'));
    // The stock Cocoa panel must no longer be what the menu item opens.
    expect(xib, isNot(contains('orderFrontStandardAboutPanel')));
  });
}
