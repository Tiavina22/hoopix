import 'package:hoopix/features/clean/domain/entities/shell_glob.dart';

/// Not a path: a flag row that turns on Finder metadata protection. Kept in
/// the same file as the paths because that is where Mole puts it, so a
/// whitelist copied between the two still means the same thing.
const finderMetadataSentinel = 'FINDER_METADATA';

/// Convenience defaults. A user who saves their own whitelist replaces these
/// entirely — that is deliberate, they are preferences rather than safety.
List<String> defaultWhitelistPatterns(String home) => [
  '$home/Library/Caches/ms-playwright*',
  '$home/.gradle/caches/*',
  '$home/.gradle/daemon/*',
  '$home/.ollama/models/*',
  '$home/Library/Caches/com.nssurge.surge-mac/*',
  '$home/Library/Application Support/com.nssurge.surge-mac/*',
  '$home/Library/Caches/org.R-project.R/R/renv/*',
  '$home/Library/Caches/JetBrains*',
  '$home/Library/Caches/com.jetbrains.toolbox*',
  '$home/Library/Caches/tealdeer/tldr-pages',
  '$home/Library/Application Support/JetBrains*',
  '$home/Library/Caches/com.apple.finder',
  '$home/Library/Mobile Documents*',
  finderMetadataSentinel,
];

/// Hard safety. These merge into a user's whitelist **unconditionally**,
/// because a saved custom file replaces the defaults above — and a row that
/// only lived there would stop protecting these the moment someone saved one
/// custom entry. Removing them breaks macOS search, font rendering or iCloud
/// sync rather than costing a rebuild, and `pypoetry/virtualenvs` holds the
/// live interpreters every Poetry project points at, not cached downloads.
List<String> safetyWhitelistPatterns(String home) => [
  finderMetadataSentinel,
  '$home/Library/Caches/com.apple.FontRegistry*',
  '$home/Library/Caches/com.apple.spotlight*',
  '$home/Library/Caches/com.apple.Spotlight*',
  '$home/Library/Caches/CloudKit*',
  '$home/Library/Caches/pypoetry/virtualenvs*',
];

/// Why a line in a whitelist file was refused. Surfaced rather than dropped
/// silently, so a typo does not quietly stop protecting something.
class WhitelistWarning {
  const WhitelistWarning(this.line, this.reason);

  final String line;
  final String reason;

  @override
  String toString() => '$reason: $line';
}

/// The user's cleanup whitelist: which paths must survive even though a
/// section would otherwise sweep them.
///
/// Ported from Mole's `is_path_whitelisted` plus the file parsing in
/// `lib/core/base.sh`, including the part that matters most: a target is
/// also protected when it is the *parent* of a whitelisted path, so
/// whitelisting a child cannot be defeated by deleting its directory.
class CleanWhitelist {
  CleanWhitelist._(this.patterns, this.warnings, {required this.protectsFinderMetadata});

  /// Builds from the raw lines of a whitelist file. Pass null when the user
  /// has no file, which is what selects the convenience defaults.
  factory CleanWhitelist.from({
    required String home,
    required List<String>? userLines,
  }) {
    final warnings = <WhitelistWarning>[];
    final patterns = <String>[];
    var finderMetadata = false;

    void accept(String raw, {required bool validate}) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) return;

      if (line.startsWith('~')) line = '$home${line.substring(1)}';
      line = line.replaceAll(r'${HOME}', home).replaceAll(r'$HOME', home);

      if (validate) {
        if (line.contains('..')) {
          warnings.add(WhitelistWarning(line, 'Path traversal not allowed'));
          return;
        }
        if (line != finderMetadataSentinel) {
          if (line.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
            warnings.add(WhitelistWarning(line, 'Invalid path format'));
            return;
          }
          if (!line.startsWith('/')) {
            warnings.add(WhitelistWarning(line, 'Must be absolute path'));
            return;
          }
        }
        if (line.contains('//')) {
          warnings.add(WhitelistWarning(line, 'Consecutive slashes'));
          return;
        }
        if (_isProtectedSystemPath(line)) {
          warnings.add(WhitelistWarning(line, 'Protected system path'));
          return;
        }
      }

      if (line == finderMetadataSentinel) {
        finderMetadata = true;
        return;
      }
      if (!patterns.contains(line)) patterns.add(line);
    }

    // A saved file replaces the convenience defaults; nothing replaces the
    // safety ones.
    for (final line in userLines ?? defaultWhitelistPatterns(home)) {
      accept(line, validate: userLines != null);
    }
    for (final line in safetyWhitelistPatterns(home)) {
      accept(line, validate: false);
    }

    return CleanWhitelist._(
      List.unmodifiable(patterns),
      List.unmodifiable(warnings),
      protectsFinderMetadata: finderMetadata,
    );
  }

  final List<String> patterns;
  final List<WhitelistWarning> warnings;

  /// Set by the [finderMetadataSentinel] row rather than by a path.
  final bool protectsFinderMetadata;

  /// Whether cleanup must leave [path] alone.
  bool covers(String path) {
    if (path.isEmpty || patterns.isEmpty) return false;
    final target = _normalize(path);

    for (final pattern in patterns) {
      final check = _normalize(pattern);
      final hasGlob =
          check.contains('*') || check.contains('?') || check.contains('[');

      if (target == check) return true;
      if (hasGlob && matchesShellGlob(target, check)) return true;

      // The target is a parent of something whitelisted. Deleting it would
      // take the whitelisted child with it, so it is protected too.
      if (check.startsWith('$target/')) return true;

      // The target sits inside a whitelisted directory. Only for literal
      // patterns: a glob's textual prefix is not a real directory.
      if (!hasGlob && target.startsWith('$check/')) return true;
    }
    return false;
  }

  /// Trailing slash removed and repeated separators collapsed, so a pattern
  /// written with single separators still matches a path a caller built by
  /// concatenation.
  static String _normalize(String value) {
    var result = value;
    while (result.contains('//')) {
      result = result.replaceAll('//', '/');
    }
    return result.length > 1 && result.endsWith('/')
        ? result.substring(0, result.length - 1)
        : result;
  }

  /// Whitelisting these would be meaningless, and accepting them hides a
  /// mistake rather than reporting it.
  static bool _isProtectedSystemPath(String line) {
    const roots = [
      '/System', '/bin', '/sbin', '/usr/bin', '/usr/sbin', '/etc', '/var/db',
    ];
    if (line == '/') return true;
    return roots.any((root) => line == root || line.startsWith('$root/'));
  }
}
