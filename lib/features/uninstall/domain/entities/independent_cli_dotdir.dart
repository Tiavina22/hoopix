/// Ports `_path_belongs_to_independent_cli` (`lib/core/app_protection.sh`):
/// standalone CLI tools shipped independently of a same-named GUI app.
/// Uninstalling `Claude.app` must never wipe `~/.claude` (Claude Code CLI's
/// own state) just because the display names collide — worse on
/// case-insensitive APFS, where `Claude` and `claude` are the same
/// directory (Mole issue #993).
const independentCliDotdirNames = {'claude', 'opencode', 'codex', 'gemini'};

/// Whether [path]'s own basename names one of [independentCliDotdirNames]
/// (with or without a leading dot, case-insensitively) and sits directly
/// under [home], `$home/.config`, `$home/.local/share`, or `$home/.cache`
/// — the exact shared roots a GUI app's own leftover-path templates can
/// otherwise collide with.
bool pathBelongsToIndependentCli(String path, {required String home}) {
  if (path.isEmpty) return false;

  final lastSlash = path.lastIndexOf('/');
  final base = lastSlash == -1 ? path : path.substring(lastSlash + 1);
  final parent = lastSlash <= 0 ? '/' : path.substring(0, lastSlash);

  final withoutDot = base.startsWith('.') ? base.substring(1) : base;
  final name = withoutDot.toLowerCase();
  if (!independentCliDotdirNames.contains(name)) return false;

  return parent == home ||
      parent == '$home/.config' ||
      parent == '$home/.local/share' ||
      parent == '$home/.cache';
}
