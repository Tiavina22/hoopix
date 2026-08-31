import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hoopix/core/locale/locale_controller.dart';
import 'package:hoopix/core/navigation/app_shell.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/theme_controller.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// hoopix's top-level widget: theme + locale + the seven-section shell.
/// Screens live under `features/`; this file only wires them together.
class HoopixApp extends StatefulWidget {
  const HoopixApp({super.key});

  @override
  State<HoopixApp> createState() => _HoopixAppState();
}

class _HoopixAppState extends State<HoopixApp> {
  final _themeController = ThemeController();
  final _localeController = LocaleController();

  @override
  void dispose() {
    _themeController.dispose();
    _localeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeController,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<Locale>(
          valueListenable: _localeController,
          builder: (context, locale, _) {
            return MaterialApp(
              title: 'Hoopix',
              debugShowCheckedModeBanner: false,
              themeMode: themeMode,
              theme: HoopixTheme.light(),
              darkTheme: HoopixTheme.dark(),
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: AppShell(
                themeController: _themeController,
                localeController: _localeController,
              ),
            );
          },
        );
      },
    );
  }
}
