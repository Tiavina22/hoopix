import 'dart:io';

import 'package:flutter/material.dart';

/// Persists the user's manual light/dark choice across launches, under
/// `~/Library/Application Support/hoopix`. Deliberately a single flat file
/// rather than a plugin dependency — there's exactly one value to store.
abstract final class ThemePreferences {
  static File _file() {
    final home = Platform.environment['HOME'];
    final dir = home == null
        ? Directory.systemTemp
        : Directory('$home/Library/Application Support/hoopix');
    return File('${dir.path}/theme_mode');
  }

  /// The saved mode, or null when nothing was saved yet (first launch) or
  /// the file can't be read — both mean "fall back to the system setting".
  static ThemeMode? load() {
    try {
      return switch (_file().readAsStringSync().trim()) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  static void save(ThemeMode mode) {
    try {
      final file = _file();
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(mode == ThemeMode.dark ? 'dark' : 'light');
    } on Object {
      // Best-effort: a failed write just means the next launch falls back
      // to the system theme instead of the last explicit choice.
    }
  }
}
