import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hoopix/core/locale/locale_preferences.dart';

const _supportedLanguageCodes = {'en', 'fr'};

/// Drives the app's UI language. Restores the user's last explicit choice
/// via [LocalePreferences]; only falls back to the OS language on a genuine
/// first launch, and only when that language is one hoopix supports.
/// Switches instantly wherever a listener rebuilds — no restart needed.
class LocaleController extends ValueNotifier<Locale> {
  LocaleController() : super(LocalePreferences.load() ?? _systemLocale());

  static Locale _systemLocale() {
    final languageCode =
        SchedulerBinding.instance.platformDispatcher.locale.languageCode;
    return _supportedLanguageCodes.contains(languageCode)
        ? Locale(languageCode)
        : const Locale('en');
  }

  void setLocale(Locale locale) {
    value = locale;
    LocalePreferences.save(locale);
  }
}
