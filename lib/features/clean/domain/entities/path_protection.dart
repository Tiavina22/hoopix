import 'dart:io';

import 'package:hoopix/features/clean/domain/entities/protected_bundles.dart';
import 'package:hoopix/features/clean/domain/entities/shell_glob.dart';

/// Whether cleanup must never touch [path].
///
/// A direct port of `should_protect_path` in Mole's
/// `lib/core/app_protection.sh`, rule for rule and in the same order — this
/// is not a heuristic, it is a list of things that broke someone's machine
/// once. Only the cleanup branch is ported: Mole's `MOLE_UNINSTALL_MODE`
/// belongs to its uninstall command, which hoopix's Clean never performs.
///
/// [home] is passed in rather than read from the environment so the rules
/// are testable without depending on whose account is running them.
bool shouldProtectPath(String path, {required String home}) {
  if (path.isEmpty) return false;

  if (_isSharedHomeStateRoot(path, home)) return true;

  // Codex Desktop keeps durable state under Application Support, but these
  // exact Chromium cache leaves are rebuildable. Only their children are
  // eligible; the profile and leaf directories themselves stay.
  final knownRebuildableCache = _matchesAny(path, [
    '$home/Library/Caches/Codex/Default/Cache/*',
    '$home/Library/Caches/Codex/Default/Code Cache/*',
    '$home/Library/Caches/Codex/Default/Partitions/codex-browser-app/Cache/*',
    '$home/Library/Caches/Codex/Default/Partitions/codex-browser-app/Code Cache/*',
    '$home/Library/Caches/Codex/codex-browser-app/Cache/*',
    '$home/Library/Caches/Codex/codex-browser-app/Code Cache/*',
  ]);

  if (isOrbstackRuntimePath(path)) return true;

  // 1. System components, by keyword.
  if (_matchesAny(path, [
    '*[Ss]ystem[Ss]ettings*',
    '*[Ss]ystem[Pp]references*',
    '*[Cc]ontrol[Cc]enter*',
    '*com.apple.[Ss]ettings*',
    '*com.apple.[Ss]ETTINGS*',
    '*com.apple.[Nn]otes*',
    '*com.apple.[Nn]OTES*',
  ])) {
    return true;
  }

  // 2. Caches macOS needs to draw its own UI. Removing these is the blank
  // System Settings panel bug.
  if (_matchesAny(path, [
    '*com.apple.systempreferences.cache*',
    '*com.apple.Settings.cache*',
    '*com.apple.controlcenter.cache*',
    '*com.apple.finder.cache*',
    '*com.apple.dock.cache*',
    '*/Library/Containers/com.apple.Settings*',
    '*/Library/Containers/com.apple.SystemSettings*',
    '*/Library/Containers/com.apple.controlcenter*',
    '*/Library/Group Containers/com.apple.systempreferences*',
    '*/Library/Group Containers/com.apple.Settings*',
    // OrbStack group containers hold live container filesystem images.
    '*/Library/Group Containers/*dev.orbstack',
    '*/Library/Group Containers/*dev.orbstack/*',
    '*/.orbstack',
    '*/.orbstack/*',
    // Shared file lists for System Settings on Sequoia.
    '*/com.apple.sharedfilelist/*com.apple.Settings*',
    '*/com.apple.sharedfilelist/*com.apple.SystemSettings*',
    '*/com.apple.sharedfilelist/*systempreferences*',
  ])) {
    return true;
  }

  // 3. Sandbox containers, checked by the bundle id in the path. Cache and
  // tmp directories inside a container are regenerable by definition, so
  // they are let through rather than blocked by the blanket `com.apple.*`
  // rule in [shouldProtectData].
  var containerCachePath = false;
  final bundleId = _containerBundleId(path);
  if (bundleId != null) {
    if (matchesShellGlob(path, '*/Data/Library/Caches/*') ||
        matchesShellGlob(path, '*/Data/tmp/*')) {
      containerCachePath = true;
    } else if (shouldProtectData(bundleId)) {
      return true;
    }
  }

  // 4. Named critical components.
  if (_matchesAny(path, [
    '*com.apple.Settings*',
    '*com.apple.SystemSettings*',
    '*com.apple.controlcenter*',
    '*com.apple.finder*',
    '*com.apple.dock*',
  ])) {
    return true;
  }

  // 4b. Endpoint-security agents.
  if (isEndpointSecurityCachePath(path)) return true;

  // 5. Preference files and user data that only look disposable.
  if (_matchesAny(path, _criticalDataPaths)) return true;

  // 6/7. Full-path and filename matches against the protected bundle lists.
  // Skipped for container cache/tmp paths: their bundle id was already
  // checked in step 3, and critical containers are caught by 1, 4 and 5.
  if (!containerCachePath && !knownRebuildableCache) {
    for (final pattern in systemCriticalBundles) {
      if (matchesShellGlob(path, pattern)) return true;
    }
    for (final pattern in dataProtectedBundles) {
      if (matchesShellGlob(path, pattern)) return true;
    }

    final filename = path.split('/').last;
    if (shouldProtectData(filename)) return true;
  }

  return false;
}

/// Paths whose cache-like names hide licences, accounts, plugin state, MDM
/// state or user content. A protection overlay only — never read this as a
/// list of things that *are* cleanable.
const _criticalDataPaths = [
  '*/Library/Preferences/com.apple.dock.plist',
  '*/Library/Preferences/com.apple.finder.plist',
  // hoopix's own logs, so cleanup cannot delete what it is writing to.
  '*/Library/Logs/hoopix',
  '*/Library/Logs/hoopix/',
  '*/Library/Logs/hoopix/*',
  // Codex keeps conversation indexes and app state in cache-shaped paths.
  '*/Library/Application Support/Codex',
  '*/Library/Application Support/Codex/*',
  '*/Library/Logs/com.openai.codex',
  '*/Library/Logs/com.openai.codex/*',
  '*/.codex/sessions',
  '*/.codex/sessions/*',
  '*/.codex/auth.json',
  '*/.codex/history.jsonl',
  '*/.codex/state_*.sqlite',
  '*/.codex/logs_*.sqlite',
  '*/.codex/session_index.jsonl',
  '*/.codex/cache/session_index.jsonl',
  '*/.codex/cache/codex_app_directory',
  '*/.codex/cache/codex_app_directory/*',
  // Bluetooth and Wi-Fi configuration.
  '*/ByHost/com.apple.bluetooth.*',
  '*/ByHost/com.apple.wifi.*',
  // NetworkExtension holds VPN tunnel state and provider preferences.
  '*/Library/Preferences/com.apple.networkextension*.plist',
  // iCloud Drive: the user's synced data.
  '*/Library/Mobile Documents*',
  '*/Mobile Documents*',
  '*/Library/Accounts',
  '*/Library/Accounts/*',
  '*/Library/Keychains',
  '*/Library/Keychains/*',
  '*/Library/Mail',
  '*/Library/Mail/*',
  '*/Library/Calendars',
  '*/Library/Contacts',
  '*/Library/Contacts/*',
  // Audio plug-ins and their licence state.
  '/Library/Audio/Plug-Ins/Components',
  '/Library/Audio/Plug-Ins/Components/*',
  '/Library/Audio/Plug-Ins/VST',
  '/Library/Audio/Plug-Ins/VST/*',
  '/Library/Audio/Plug-Ins/VST3',
  '/Library/Audio/Plug-Ins/VST3/*',
  '/Library/Application Support/iZotope',
  '/Library/Application Support/iZotope/*',
  '*/Library/Application Support/iZotope',
  '*/Library/Application Support/iZotope/*',
  '/Library/Application Support/LaserSoft Imaging',
  '/Library/Application Support/LaserSoft Imaging/*',
  '*/Library/Preferences/com.native-instruments*',
  '*/Library/Preferences/com.avid.mediacomposer*.plist',
  '*/Library/Preferences/com.fabfilter.*.[0-9].plist',
  '*/Library/Preferences/com.fabfilter.*.[0-9][0-9].plist',
  '*/Library/Preferences/com.paceap.*.plist',
  '/private/var/folders/*/C/com.native-instruments*',
  '/private/var/folders/*/C/com.avid.mediacomposer*',
  '/private/var/folders/*/C/com.paceap.eden.iLokLicenseManager*',
  '*/Library/Caches/ms-playwright',
  '*/Library/Caches/ms-playwright/*',
  '*/Library/Caches/app.cotypist.Cotypist',
  '*/Library/Caches/app.cotypist.Cotypist/*',
  '*/Library/Caches/com.displaylink.DisplayLinkUserAgent',
  '*/Library/Caches/com.displaylink.DisplayLinkUserAgent/*',
  '*/Library/Caches/com.lasersoft-imaging.SilverFast9',
  '*/Library/Caches/com.lasersoft-imaging.SilverFast9/*',
  '*/Library/Caches/com.lasersoft-imaging.SilverFast-9-Installer',
  '*/Library/Caches/com.lasersoft-imaging.SilverFast-9-Installer/*',
  '*/Library/Caches/Adobe *',
  '*/Library/Caches/* Adobe*',
  '*/Library/Caches/com.apple.containermanagerd',
  '*/Library/Caches/com.apple.containermanagerd/*',
  '*/Library/Caches/com.apple.homed',
  '*/Library/Caches/com.apple.homed/*',
  '*/Library/Caches/com.apple.ap.adprivacyd',
  '*/Library/Caches/com.apple.ap.adprivacyd/*',
  '*/Library/Caches/FamilyCircle',
  '*/Library/Caches/FamilyCircle/*',
  '*/Library/Caches/com.apple.HomeKit',
  '*/Library/Caches/com.apple.HomeKit/*',
  '*/Library/Caches/com.apple.WorkflowKit.BackgroundShortcutRunner.ShortcutsSandboxCache',
  '*/Library/Caches/com.apple.WorkflowKit.BackgroundShortcutRunner.ShortcutsSandboxCache/*',
  '*/Library/Caches/com.apple.siriactionsd.ShortcutsSandboxCache',
  '*/Library/Caches/com.apple.siriactionsd.ShortcutsSandboxCache/*',
  // Wallpaper and aerial screen-saver assets are user-selected content. A
  // download-time mtime says nothing about whether they are in use, and
  // removing them forces a large re-download and resets the selection.
  '*/Library/Application Support/com.apple.idleassetsd',
  '*/Library/Application Support/com.apple.idleassetsd/*',
  '*/Library/Application Support/com.apple.wallpaper',
  '*/Library/Application Support/com.apple.wallpaper/*',
  // CoreAudio: cleaning these has cost people audio output entirely.
  '*com.apple.coreaudio*',
  '*com.apple.audio.*',
  '*coreaudiod*',
];

/// Whether a bundle id (or a bare filename) belongs to something whose data
/// must survive cleanup. Port of `should_protect_data`.
bool shouldProtectData(String bundleId) {
  const keywordRules = [
    'com.apple.*',
    'loginwindow',
    'dock',
    'systempreferences',
    'finder',
    'safari',
    // CUPS is an OS subsystem with no app of its own; without this its
    // printing preferences look orphaned.
    'org.cups.*',
    'backgroundtaskmanagement*',
    'keychain*',
    'security*',
    'bluetooth*',
    'wifi*',
    'network*',
    'tcc',
    'notification*',
    'accessibility*',
    'universalaccess*',
    'HIToolbox*',
    '*inputmethod*',
    '*InputMethod*',
    '*IME',
    'textinput*',
    'TextInput*',
    'keyboard*',
    'Keyboard*',
    'inputsource*',
    'InputSource*',
    'keylayout*',
    'KeyLayout*',
    'GlobalPreferences',
    '.GlobalPreferences',
    'org.pqrs.Karabiner*',
    'com.1password.*',
    'com.agilebits.*',
    'com.lastpass.*',
    'com.dashlane.*',
    'com.bitwarden.*',
    'com.jetbrains.*',
    'JetBrains*',
    'com.microsoft.*',
    'com.visualstudio.*',
    'com.sublimetext.*',
    'com.sublimehq.*',
    'Cursor',
    'Claude',
    'ChatGPT',
    'com.openai.codex',
    'Codex',
    'codex-runtimes',
    'Ollama',
    'com.clash.app',
    'com.nssurge.*',
    'com.v2ray.*',
    'com.clash.*',
    'ClashX*',
    'Surge*',
    'Shadowrocket*',
    'Quantumult*',
    'clash-*',
    'Clash-*',
    '*-clash',
    '*-Clash',
    'clash.*',
    'Clash.*',
    'clash_*',
    '*clash-verge*',
    '*Clash-Verge*',
    'clashverge*',
    'ClashVerge*',
    'com.docker.*',
    'com.getpostman.*',
    'com.insomnia.*',
  ];

  for (final rule in keywordRules) {
    if (matchesShellGlob(bundleId, rule)) return true;
  }

  for (final pattern in dataProtectedBundles) {
    if (matchesShellGlob(bundleId, pattern)) return true;
  }
  return false;
}

/// OrbStack keeps live container filesystem images here. Case-insensitive,
/// as in Mole, because these are user-visible container names.
bool isOrbstackRuntimePath(String path) {
  const patterns = [
    '*/Library/Group Containers/*dev.orbstack',
    '*/Library/Group Containers/*dev.orbstack/*',
    '*/.orbstack',
    '*/.orbstack/*',
  ];
  final lower = path.toLowerCase();
  return patterns.any((p) => matchesShellGlob(lower, p.toLowerCase()));
}

/// E5RT (Apple's Espresso runtime, behind Vision and text recognition) keeps
/// compiled model bundles here. A process that already resolved this cache
/// does not rebuild it: deleting it under a running app makes every later
/// recognition call fail until the app restarts. Reclaims little, breaks
/// visibly — so the directory and its immediate parent are both off limits.
bool holdsCompiledModelCache(String path, {bool Function(String)? directoryExists}) {
  if (path.isEmpty) return false;
  final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  if (trimmed.endsWith('/com.apple.e5rt.e5bundlecache')) return true;

  final exists = directoryExists ?? (p) => Directory(p).existsSync();
  return exists('$trimmed/com.apple.e5rt.e5bundlecache');
}

/// EDR/MDM agents tamper-protect their on-disk state. Deleting anything of
/// theirs under the per-user Darwin folder — a rebuildable shader cache, a
/// code-signature clone, a temp file — trips sensor tamper detection that
/// corporate security reports as malware. A few MB reclaimed is not worth
/// that, so a deliberately wide match is the safe direction here.
bool isEndpointSecurityCachePath(String path) {
  final lower = path.toLowerCase();
  if (!lower.startsWith('/private/var/folders/') &&
      !lower.startsWith('/var/folders/')) {
    return false;
  }
  return endpointSecurityBundlePrefixes
      .any((prefix) => lower.contains(prefix.toLowerCase()));
}

/// Shared XDG and user-local roots hold state belonging to many unrelated
/// tools. An app display name such as "Local", "Config" or "Cache" can spell
/// one of these with different casing and still resolve to the same
/// directory on a case-insensitive volume. The roots are protected; their
/// app-specific children (`~/.config/zed`) are not.
bool _isSharedHomeStateRoot(String path, String home) {
  final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  const roots = [
    '.[Cc][Aa][Cc][Hh][Ee]',
    '.[Cc][Oo][Nn][Ff][Ii][Gg]',
    '.[Ll][Oo][Cc][Aa][Ll]',
    '.[Ll][Oo][Cc][Aa][Ll]/[Bb][Ii][Nn]',
    '.[Ll][Oo][Cc][Aa][Ll]/[Ll][Ii][Bb]',
    '.[Ll][Oo][Cc][Aa][Ll]/[Ss][Hh][Aa][Rr][Ee]',
    '.[Ll][Oo][Cc][Aa][Ll]/[Ss][Tt][Aa][Tt][Ee]',
  ];
  return roots.any((root) => matchesShellGlob(trimmed, '$home/$root'));
}

/// The bundle id owning a sandbox container path, or null when the path is
/// not inside one.
String? _containerBundleId(String path) {
  for (final marker in ['/Library/Containers/', '/Library/Group Containers/']) {
    final index = path.indexOf(marker);
    if (index == -1) continue;
    final rest = path.substring(index + marker.length);
    if (rest.isEmpty) continue;
    final end = rest.indexOf('/');
    return end == -1 ? rest : rest.substring(0, end);
  }
  return null;
}

bool _matchesAny(String path, List<String> patterns) =>
    patterns.any((pattern) => matchesShellGlob(path, pattern));
