import 'dart:io';

import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';

/// Paths `mo clean` already handles. A row inside one of these is not
/// offered as a manual cleanup, because the cleanup command owns it.
const _handledByClean = [
  '/Library/Caches/',
  '/Library/Logs/',
  '/Library/Saved Application State/',
  '/.Trash/',
  '/Library/DiagnosticReports/',
];

/// Dependency and build directories: regenerable from the project itself.
const _projectDependencyDirs = {
  'node_modules', 'bower_components', '.yarn', '.pnpm-store',
  'venv', '.venv', 'virtualenv', '__pycache__', '.pytest_cache',
  '.mypy_cache', '.ruff_cache', '.tox', '.eggs', 'htmlcov',
  '.ipynb_checkpoints',
  'vendor', '.bundle',
  '.gradle', 'out',
  'build', 'dist', 'target', '.next', '.nuxt', '.output', '.parcel-cache',
  '.turbo', '.vite', '.nx', 'coverage', '.coverage', '.nyc_output',
  '.angular', '.svelte-kit', '.astro', '.docusaurus',
  'DerivedData', 'Pods', '.build', 'Carthage', '.dart_tool',
  '.terraform',
};

/// The freedesktop marker a tool drops to say "this whole tree is a cache".
const _cacheDirTagName = 'CACHEDIR.TAG';
const _cacheDirTagSignature = 'Signature: 8a477f597d28d172789f06886806bc55';

/// A directory whose contents can be regenerated, so removing it costs time
/// rather than data. Mirrors `isCleanableDir` in Mole's analyzer.
bool isCleanableDirectory(AnalyzeEntry entry) {
  if (!entry.isDirectory || entry.path.isEmpty) return false;

  // What `mo clean` covers is not offered here, so the two never disagree
  // about who owns a path.
  if (_handledByClean.any(entry.path.contains)) return false;

  if (_hasCacheDirTag(entry.path)) return true;
  return _projectDependencyDirs.contains(entry.name);
}

bool _hasCacheDirTag(String directory) {
  try {
    final tag = File('$directory/$_cacheDirTagName');
    if (!tag.existsSync()) return false;
    // Only the signature is read; the rest of the file is free-form.
    final head = tag.openSync();
    try {
      final bytes = head.readSync(_cacheDirTagSignature.length);
      return String.fromCharCodes(bytes) == _cacheDirTagSignature;
    } finally {
      head.closeSync();
    }
  } on Object {
    return false;
  }
}

/// How long a row has gone untouched, as a short label, or null when it is
/// recent enough not to be worth mentioning.
///
/// Nothing under 90 days is reported: below that, an untouched file is
/// ordinary rather than a signal. Same thresholds as Mole's
/// `formatUnusedTime`.
String? unusedForLabel(DateTime? accessed, {DateTime? now}) {
  if (accessed == null) return null;

  final days = (now ?? DateTime.now()).difference(accessed).inDays;
  if (days < 90) return null;

  final years = days ~/ 365;
  if (years >= 2) return '>${years}yr';
  if (years >= 1) return '>1yr';

  final months = days ~/ 30;
  if (months >= 3) return '>${months}mo';
  return null;
}
