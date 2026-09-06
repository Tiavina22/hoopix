import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/features/clean/domain/entities/path_protection.dart';
import 'package:hoopix/features/uninstall/domain/entities/independent_cli_dotdir.dart';

/// Ports the exact-path template half of `find_app_files`
/// (`lib/core/app_protection.sh`): every fixed Library/XDG location an app
/// might leave data in, keyed by its display name and/or bundle id.
///
/// Returns path *candidates* only — nothing here checks the filesystem, so
/// a caller must still filter by existence before treating any of these as
/// a real leftover. Every candidate that passed here has already cleared
/// the same three guards Mole's own loop applies before adding a path:
/// never a bare generic Library/XDG root ([_genericDirectoryRoots]), never
/// a shared XDG state root ([isSharedHomeStateRoot]), and never an
/// independent CLI tool's own dotdir sharing the app's display name
/// ([pathBelongsToIndependentCli]).
///
/// Not ported in this pass: the bundle-leaf-derived variant (tdesktop-fork
/// heuristic), the Zed cross-channel HTTPStorages carve-out, vendor-nested
/// support directories, bundle-id-boundary-matched dynamic patterns
/// (Preferences/ByHost, LaunchAgents, Group Containers, embedded bundle
/// ids, shared file lists), the name-only LaunchAgent glob, and the
/// per-vendor/toolchain special cases (Xcode, Android Studio, JetBrains,
/// ...). Each is its own reasoned scope, following Mole's own source
/// section by section rather than approximated.
List<String> uninstallLeftoverPathCandidates({
  required String home,
  required String bundleId,
  required String appName,
}) {
  final candidates = <String>[];
  final bundleIdValid = isReverseDnsBundleId(bundleId);

  if (appName.length >= 2) {
    candidates.addAll(_appNamePatterns(home, appName));
  }
  if (bundleIdValid) {
    candidates.addAll(_bundleIdPatterns(home, bundleId));
  }
  if (appName.length > 3 && appName.contains(' ')) {
    candidates.addAll(_compoundNamePatterns(home, appName));
  }

  final baseName = _stripVersionSuffix(appName);
  if (baseName != appName && baseName.length > 2) {
    candidates.addAll(_baseNamePatterns(home, baseName));
  }

  return [
    for (final path in candidates)
      if (_passesGuards(path, home: home)) path,
  ];
}

List<String> _appNamePatterns(String home, String appName) {
  final lowercaseName = appName.toLowerCase();
  return [
    '$home/Library/Application Support/$appName',
    '$home/Library/Caches/$appName',
    '$home/Library/Logs/$appName',
    '$home/Library/Preferences/$appName',
    '$home/Library/Preferences/$appName.plist',
    '$home/Library/Saved Application State/$appName.savedState',
    '$home/Library/Services/$appName.workflow',
    '$home/Library/QuickLook/$appName.qlgenerator',
    '$home/Library/Internet Plug-Ins/$appName.plugin',
    '$home/Library/Audio/Plug-Ins/Components/$appName.component',
    '$home/Library/Audio/Plug-Ins/VST/$appName.vst',
    '$home/Library/Audio/Plug-Ins/VST3/$appName.vst3',
    '$home/Library/Audio/Plug-Ins/Digidesign/$appName.dpm',
    '$home/Library/PreferencePanes/$appName.prefPane',
    '$home/Library/Input Methods/$appName.app',
    '$home/Library/Screen Savers/$appName.saver',
    '$home/Library/Frameworks/$appName.framework',
    '$home/Library/Contextual Menu Items/$appName.plugin',
    '$home/Library/Spotlight/$appName.mdimporter',
    '$home/Library/ColorPickers/$appName.colorPicker',
    '$home/Library/Workflows/$appName.workflow',
    '$home/.config/$appName',
    '$home/.cache/$appName',
    '$home/.cache/$lowercaseName',
    '$home/.local/share/$appName',
    '$home/Library/Address Book Plug-Ins/$appName.bundle',
    '$home/Library/Accessibility/$appName.bundle',
    '$home/Library/Mail/Bundles/$appName.mailbundle',
  ];
}

List<String> _bundleIdPatterns(String home, String bundleId) => [
  '$home/Library/Application Support/$bundleId',
  '$home/Library/Caches/$bundleId',
  '$home/Library/Logs/$bundleId',
  '$home/Library/Saved Application State/$bundleId.savedState',
  '$home/Library/Containers/$bundleId',
  '$home/Library/WebKit/$bundleId',
  '$home/Library/WebKit/com.apple.WebKit.WebContent/$bundleId',
  '$home/Library/HTTPStorages/$bundleId',
  '$home/Library/HTTPStorages/$bundleId.binarycookies',
  '$home/Library/Cookies/$bundleId.binarycookies',
  '$home/Library/Application Scripts/$bundleId',
  '$home/Library/Input Methods/$bundleId.app',
  '$home/Library/Autosave Information/$bundleId',
  '$home/Library/SyncedPreferences/$bundleId.plist',
];

List<String> _compoundNamePatterns(String home, String appName) {
  final nospace = appName.replaceAll(' ', '');
  final underscore = appName.replaceAll(' ', '_');
  final hyphen = appName.replaceAll(' ', '-');
  final lowercaseNospace = nospace.toLowerCase();
  final lowercaseUnderscore = underscore.toLowerCase();
  final lowercaseHyphen = hyphen.toLowerCase();

  return [
    '$home/Library/Application Support/$nospace',
    '$home/Library/Caches/$nospace',
    '$home/Library/Logs/$nospace',
    '$home/Library/Preferences/$nospace',
    '$home/Library/Preferences/$nospace.plist',
    '$home/Library/Saved Application State/$nospace.savedState',
    '$home/Library/Application Support/$underscore',
    '$home/Library/Application Support/$hyphen',
    '$home/Library/Preferences/$underscore',
    '$home/Library/Preferences/$underscore.plist',
    '$home/Library/Preferences/$hyphen',
    '$home/Library/Preferences/$hyphen.plist',
    '$home/.config/$lowercaseNospace',
    '$home/.config/$lowercaseHyphen',
    '$home/.config/$lowercaseUnderscore',
    '$home/.cache/$lowercaseNospace',
    '$home/.cache/$lowercaseHyphen',
    '$home/.cache/$lowercaseUnderscore',
    '$home/.local/share/$lowercaseNospace',
    '$home/.local/share/$lowercaseHyphen',
    '$home/.local/share/$lowercaseUnderscore',
  ];
}

List<String> _baseNamePatterns(String home, String baseName) {
  final baseLowercase = baseName.toLowerCase();
  return [
    '$home/Library/Application Support/$baseName',
    '$home/Library/Caches/$baseName',
    '$home/Library/Logs/$baseName',
    '$home/Library/Preferences/$baseName',
    '$home/Library/Preferences/$baseName.plist',
    '$home/Library/Saved Application State/$baseName.savedState',
    '$home/.config/$baseLowercase',
    '$home/.cache/$baseLowercase',
    '$home/.local/share/$baseLowercase',
  ];
}

/// Extracts a base name by removing a trailing version/channel word —
/// `"Zed Nightly"` → `"Zed"`, `"Firefox Developer Edition"` → `"Firefox"`.
final _versionSuffix = RegExp(
  r'^(.+)\s+(Nightly|Beta|Alpha|Dev|Canary|Preview|Insider|Edge|Stable|'
  r'Release|RC|LTS|Developer Edition|Technology Preview)$',
);

String _stripVersionSuffix(String appName) {
  final match = _versionSuffix.firstMatch(appName);
  return match?.group(1) ?? appName;
}

/// A bare Library/XDG root — never a real candidate on its own. Every one
/// of these existing means `app_name`/`bundle_id` was effectively empty
/// when a template was built, not that the whole directory is this app's.
final _genericDirectoryRoots = {
  '/Library/Application Support',
  '/Library/Caches',
  '/Library/Logs',
  '/Library/Preferences',
  '/Library/Preferences/ByHost',
  '/Library/Containers',
  '/Library/WebKit',
  '/Library/HTTPStorages',
  '/Library/Application Scripts',
  '/Library/Autosave Information',
  '/Library/Group Containers',
  '/.config',
  '/.cache',
  '/.local/share',
};

bool _passesGuards(String path, {required String home}) {
  final trimmed = path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  if (trimmed == home || trimmed == '$home/.') return false;
  for (final root in _genericDirectoryRoots) {
    if (trimmed == '$home$root') return false;
  }
  if (isSharedHomeStateRoot(trimmed, home)) return false;
  if (pathBelongsToIndependentCli(trimmed, home: home)) return false;
  return true;
}
