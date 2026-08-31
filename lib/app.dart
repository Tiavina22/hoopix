import 'package:flutter/material.dart';
import 'package:hoopix/core/navigation/app_shell.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/theme_controller.dart';

/// hoopix's top-level widget: theme + the seven-section shell. Screens live
/// under `features/`; this file only wires them together.
class HoopixApp extends StatefulWidget {
  const HoopixApp({super.key});

  @override
  State<HoopixApp> createState() => _HoopixAppState();
}

class _HoopixAppState extends State<HoopixApp> {
  final _themeController = ThemeController();

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeController,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Hoopix',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: HoopixTheme.light(),
          darkTheme: HoopixTheme.dark(),
          home: AppShell(themeController: _themeController),
        );
      },
    );
  }
}
