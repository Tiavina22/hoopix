import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hoopix/core/theme/theme_preferences.dart';

/// Drives the app's light/dark mode. Restores the user's last explicit
/// choice via [ThemePreferences]; only falls back to the OS setting on a
/// genuine first launch. Switches instantly wherever a listener rebuilds —
/// no restart needed.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemePreferences.load() ?? _systemThemeMode());

  static ThemeMode _systemThemeMode() {
    final brightness = SchedulerBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  }

  bool get isDark => value == ThemeMode.dark;

  void setDark(bool isDark) {
    value = isDark ? ThemeMode.dark : ThemeMode.light;
    ThemePreferences.save(value);
  }
}
