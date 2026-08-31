import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Drives the app's light/dark mode. Starts from the OS setting so the app
/// matches the system on first launch, then switches instantly wherever a
/// listener rebuilds — no restart needed.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(_systemThemeMode());

  static ThemeMode _systemThemeMode() {
    final brightness = SchedulerBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  }

  bool get isDark => value == ThemeMode.dark;

  void setDark(bool isDark) {
    value = isDark ? ThemeMode.dark : ThemeMode.light;
  }
}
