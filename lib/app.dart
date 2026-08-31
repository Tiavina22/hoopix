import 'package:flutter/material.dart';
import 'package:hoopix/core/navigation/app_shell.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';

/// hoopix's top-level widget: theme + the six-section shell. Screens live
/// under `features/`; this file only wires them together.
class HoopixApp extends StatelessWidget {
  const HoopixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hoopix',
      debugShowCheckedModeBanner: false,
      theme: HoopixTheme.light(),
      darkTheme: HoopixTheme.dark(),
      home: const AppShell(),
    );
  }
}
