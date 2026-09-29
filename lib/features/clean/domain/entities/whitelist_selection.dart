import 'package:hoopix/features/clean/domain/entities/clean_whitelist.dart';
import 'package:hoopix/features/clean/domain/entities/whitelist_catalog.dart';

/// What the whitelist editor shows and saves — port of Mole's
/// `manage_whitelist_categories` (`lib/manage/whitelist.sh`).
///
/// A catalog row is checked when the file holds its exact pattern. Every
/// other line is a custom pattern: kept, shown, and written back as it was.
/// The hard-safety patterns are neither: they protect whatever the file
/// says, so they are shown as always on and never written, which keeps a
/// mandatory rule from turning into an editable one on first save.
class WhitelistSelection {
  const WhitelistSelection._({
    required this.home,
    required this.isDefault,
    required Set<String> checked,
    required this.custom,
  }) : _checked = checked;

  /// Reads [fileLines], or the convenience defaults when the user has no
  /// file yet ([fileLines] null), which is what Clean itself applies then.
  factory WhitelistSelection.load({
    required String home,
    required List<String>? fileLines,
  }) {
    final current = <String>[];
    for (final raw in fileLines ?? defaultWhitelistPatterns(home)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (current.any(
        (existing) => whitelistPatternsEquivalent(existing, line, home: home),
      )) {
        continue;
      }
      current.add(line);
    }

    final safety = safetyWhitelistPatterns(home);
    bool inCatalog(String line) => whitelistCatalog.any(
      (item) => whitelistPatternsEquivalent(item.pattern, line, home: home),
    );
    bool isSafety(String line) => safety.any(
      (pattern) => whitelistPatternsEquivalent(pattern, line, home: home),
    );

    return WhitelistSelection._(
      home: home,
      isDefault: fileLines == null,
      checked: {
        for (final item in whitelistCatalog)
          if (current.any(
            (line) =>
                whitelistPatternsEquivalent(item.pattern, line, home: home),
          ))
            item.pattern,
      },
      custom: List.unmodifiable([
        for (final line in current)
          if (!inCatalog(line) && !isSafety(line)) line,
      ]),
    );
  }

  final String home;

  /// True while no whitelist file exists, so the defaults are in force.
  final bool isDefault;

  /// User patterns outside the catalog, in file order.
  final List<String> custom;

  final Set<String> _checked;

  /// Protected by the hard-safety rules whatever is saved, so its checkbox
  /// cannot be cleared.
  bool isAlwaysProtected(WhitelistCatalogItem item) {
    final safetyOnly = CleanWhitelist.from(home: home, userLines: const []);
    if (item.pattern == finderMetadataSentinel) {
      return safetyOnly.protectsFinderMetadata;
    }
    final expanded = expandWhitelistHome(item.pattern, home: home);
    final glob = expanded.indexOf(RegExp(r'[*?\[]'));
    var prefix = glob < 0 ? expanded : expanded.substring(0, glob);
    if (prefix.endsWith('/')) prefix = prefix.substring(0, prefix.length - 1);
    return safetyOnly.covers(prefix);
  }

  bool isChecked(WhitelistCatalogItem item) =>
      isAlwaysProtected(item) || _checked.contains(item.pattern);

  WhitelistSelection toggled(WhitelistCatalogItem item) {
    if (isAlwaysProtected(item)) return this;
    final checked = {..._checked};
    if (!checked.remove(item.pattern)) checked.add(item.pattern);
    return _copy(checked: checked);
  }

  /// Adds [raw] as a custom pattern, or explains why it was refused with
  /// the same rules Clean applies when it reads the file. A pattern the
  /// catalog already lists checks that row instead of duplicating it.
  ({WhitelistSelection selection, String? refusal}) withCustom(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return (selection: this, refusal: null);

    final warnings = CleanWhitelist.from(
      home: home,
      userLines: [line],
    ).warnings;
    if (warnings.isNotEmpty) {
      return (selection: this, refusal: warnings.first.reason);
    }

    for (final item in whitelistCatalog) {
      if (whitelistPatternsEquivalent(item.pattern, line, home: home)) {
        return (
          selection: _copy(checked: {..._checked, item.pattern}),
          refusal: null,
        );
      }
    }
    if (custom.any(
      (existing) => whitelistPatternsEquivalent(existing, line, home: home),
    )) {
      return (selection: this, refusal: null);
    }
    return (selection: _copy(custom: [...custom, line]), refusal: null);
  }

  WhitelistSelection withoutCustom(String line) => _copy(
    custom: [
      for (final existing in custom)
        if (existing != line) existing,
    ],
  );

  /// The whole file to save: a header, then the checked catalog patterns in
  /// catalog order, then the custom ones. Always-protected rows are left
  /// out, since the safety rules apply to them whatever the file says.
  List<String> toFileLines() => [
    '# Hoopix Whitelist - Protected paths won\'t be deleted',
    '# Default protections: Playwright browsers, Ollama models, Surge Mac, '
        'R renv, Finder metadata',
    '# Add one pattern per line to keep items safe.',
    '',
    for (final item in whitelistCatalog)
      if (_checked.contains(item.pattern) && !isAlwaysProtected(item))
        item.pattern,
    ...custom,
  ];

  WhitelistSelection _copy({Set<String>? checked, List<String>? custom}) =>
      WhitelistSelection._(
        home: home,
        isDefault: isDefault,
        checked: checked ?? _checked,
        custom: List.unmodifiable(custom ?? this.custom),
      );
}
