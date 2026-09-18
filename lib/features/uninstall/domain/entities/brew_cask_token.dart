/// The two Caskroom roots Mole recognises (`_extract_cask_token_from_path`,
/// `lib/uninstall/brew.sh`): Apple Silicon and Intel Homebrew prefixes.
const caskroomRoots = ['/opt/homebrew/Caskroom', '/usr/local/Caskroom'];

final _caskToken = RegExp(r'^[a-z0-9][a-z0-9-]*$');

/// Ports `_extract_cask_token_from_path`: the `<token>` in
/// `<Caskroom>/<token>/<version>/...`, or null when [path] is not inside a
/// Caskroom or the component does not look like a cask token. Tokens with
/// `@` (`temurin@21`) are rejected exactly as Mole rejects them.
String? caskTokenFromCaskroomPath(String path) {
  for (final root in caskroomRoots) {
    if (!path.startsWith('$root/')) continue;
    final token = path.substring(root.length + 1).split('/').first;
    return _caskToken.hasMatch(token) ? token : null;
  }
  return null;
}

/// `grep -qxF "$token" <<< "$(brew list --cask)"`: whether [token] is one
/// exact line of `brew list --cask` output.
bool caskListContains(String caskList, String token) =>
    token.isNotEmpty &&
    caskList.split('\n').any((line) => line.trim() == token);

/// `grep -Fix "$app_name_lower" <<< "$cask_list"`: the installed cask whose
/// token equals the app bundle's own name, case-insensitively — or null.
/// Returns the line as Homebrew printed it, as `grep` does.
String? caskListMatchingName(String caskList, String bundleName) {
  final wanted =
      (bundleName.endsWith('.app')
              ? bundleName.substring(0, bundleName.length - '.app'.length)
              : bundleName)
          .toLowerCase();
  if (wanted.isEmpty) return null;
  for (final line in caskList.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.toLowerCase() == wanted) return trimmed;
  }
  return null;
}

/// The ownership check `_detect_cask_via_caskroom_search` and
/// `_detect_cask_via_brew_list` both apply to `brew info --cask` output
/// before trusting a name-based match: the info must mention [appPath]
/// itself, or — only for an app directly in `/Applications` — its bundle
/// name, which is how Homebrew lists an `(App)` artifact.
bool brewInfoOwnsApp(String info, String appPath) {
  if (info.contains(appPath)) return true;
  final bundleName = appPath.split('/').last;
  return appPath == '/Applications/$bundleName' && info.contains(bundleName);
}
