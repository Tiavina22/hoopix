import 'dart:io';

import 'package:flutter/material.dart';

/// Persists the user's manual language choice across launches, under
/// `~/Library/Application Support/hoopix`. Same rationale as
/// `ThemePreferences`: one value, a flat file, no plugin dependency.
abstract final class LocalePreferences {
  static File _file() {
    final home = Platform.environment['HOME'];
    final dir = home == null
        ? Directory.systemTemp
        : Directory('$home/Library/Application Support/hoopix');
    return File('${dir.path}/locale');
  }

  /// The saved locale, or null when nothing was saved yet (first launch),
  /// the file can't be read, or its content isn't a supported language code
  /// — all of which mean "fall back to the system locale".
  static Locale? load() {
    try {
      return switch (_file().readAsStringSync().trim()) {
        'fr' => const Locale('fr'),
        'en' => const Locale('en'),
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  static void save(Locale locale) {
    try {
      final file = _file();
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(locale.languageCode);
    } on Object {
      // Best-effort: a failed write just means the next launch falls back
      // to the system locale instead of the last explicit choice.
    }
  }
}
