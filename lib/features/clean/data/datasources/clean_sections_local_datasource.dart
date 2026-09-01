import 'dart:io';

import 'package:hoopix/features/clean/domain/entities/deno_cache_root.dart';
import 'package:hoopix/features/clean/domain/entities/path_protection.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Enumerates what each section proposes to remove.
///
/// Enumeration only: nothing here judges safety or deletes. Every path it
/// returns still goes through the protection funnel, and the funnel's answer
/// is what the user sees.
///
/// Sections and their targets follow Mole's `lib/clean/*.sh`. They are added
/// one at a time rather than guessed at wholesale — each is a hand-curated
/// list, not a rule that can be inferred.
class CleanSectionsLocalDataSource {
  CleanSectionsLocalDataSource({
    required this.home,
    this.denoDir,
    Directory Function(String path)? directory,
  }) : _directory = directory ?? Directory.new;

  final String home;

  /// Read from the environment by the repository, so "DENO_DIR is set to
  /// something odd" is a state this can be handed in a test.
  final String? denoDir;

  final Directory Function(String path) _directory;

  /// Everything the run would consider, section by section, in the order
  /// Mole works through them.
  List<CleanSectionTargets> enumerate() => [
    CleanSectionTargets(userEssentials, _userEssentialsTargets()),
    CleanSectionTargets(appCaches, _appCachesTargets()),
    CleanSectionTargets(browsers, _browsersTargets()),
    CleanSectionTargets(cloudAndOffice, _cloudAndOfficeTargets()),
    CleanSectionTargets(virtualization, _virtualizationTargets()),
    CleanSectionTargets(applicationSupport, _applicationSupportTargets()),
    CleanSectionTargets(deviceFirmware, _deviceFirmwareTargets()),
  ];

  static const userEssentials = 'User essentials';
  static const appCaches = 'App caches';
  static const browsers = 'Browsers';
  static const cloudAndOffice = 'Cloud & Office';
  static const applicationSupport = 'Application Support';
  static const virtualization = 'Virtualization';
  static const deviceFirmware = 'Device backups & firmware';

  List<String> _userEssentialsTargets() {
    final targets = <String>[];

    final deno = denoCacheRoot(home: home, denoDir: denoDir);
    if (deno == null) {
      // Refusing is right, but sweeping past an unresolved owner root would
      // be worse: the whole cache batch stays empty rather than risk taking
      // Deno's runtime payloads with it.
      //
      // The other categories below are unaffected — they do not overlap it.
    } else {
      for (final child in _childrenOf('$home/Library/Caches')) {
        // The Deno root itself is review-only, not swept.
        if (child == deno || child.startsWith('$deno/')) continue;
        targets.add(child);
      }
    }

    targets.addAll(_childrenOf('$home/Library/Logs'));

    // Recent-items lists: what was opened, not what is needed to open it.
    const shared = 'Library/Application Support/com.apple.sharedfilelist';
    for (final kind in ['Applications', 'Documents', 'Servers', 'Hosts']) {
      for (final extension in ['sfl2', 'sfl']) {
        targets.add(
          '$home/$shared/com.apple.LSSharedFileList.Recent$kind.$extension',
        );
      }
    }
    targets.add('$home/Library/Preferences/com.apple.recentitems.plist');

    return targets;
  }

  /// Everything Mole's `clean_app_caches` proposes.
  ///
  /// A named target under `Library/Caches` is repeated here only when the
  /// top-level sweep in [userEssentials] cannot actually reach it: any
  /// `com.apple.*` (or otherwise vendor-protected) top-level Caches child is
  /// always kept, not cleaned, by [shouldProtectPath]'s blanket bundle-id
  /// rule — the whole point of this curated allowlist is the set of
  /// specific children known safe to reach around that block. A target that
  /// blanket rule does *not* cover (`GeoServices`, `Quick Look`, ...) is
  /// left out here on purpose: [userEssentials] already proposes it whole,
  /// and repeating it would double-count its size across two sections.
  ///
  /// Not ported: `_clean_incomplete_downloads` needs an open-file-handle
  /// probe hoopix does not have yet, so an in-progress Safari/Chrome
  /// download is not a safe target here.
  List<String> _appCachesTargets() {
    final targets = <String>[];

    targets.add('$home/Library/Caches/com.apple.photoanalysisd');
    targets.add('$home/Library/Caches/com.apple.akd');
    targets.add('$home/Library/Caches/com.apple.QuickLook.thumbnailcache');
    for (final child in _childrenOf('$home/Library/Caches')) {
      if (child.split('/').last.startsWith('com.apple.iconservices')) {
        targets.add(child);
      }
    }
    targets.addAll(
      _childrenOf('$home/Library/Caches/com.apple.WebKit.Networking'),
    );

    targets.addAll(_childrenOf('$home/Library/Saved Application State'));
    targets.addAll(_childrenOf('$home/Library/DiagnosticReports'));
    targets.addAll(_childrenOf('$home/Library/IdentityCaches'));
    targets.addAll(_childrenOf('$home/Library/Suggestions'));
    targets.add('$home/Library/Calendars/Calendar Cache');
    for (final source in _childrenOf(
      '$home/Library/Application Support/AddressBook/Sources',
    )) {
      targets.add('$source/Photos.cache');
    }

    targets.addAll(_supportAppDataTargets());
    targets.addAll(_childrenOf('$home/Library/Caches/com.apple.helpd'));
    targets.addAll(
      _childrenOf('$home/Library/Caches/com.apple.AppleMediaServices'),
    );
    targets.addAll(_childrenOf('$home/Library/Caches/com.apple.duetexpertd'));
    targets.addAll(_childrenOf('$home/Library/Caches/com.apple.parsecd'));
    targets.addAll(_childrenOf('$home/Library/Caches/com.apple.python'));
    targets.addAll(_sandboxedAppleCacheTargets());
    targets.addAll(_containerCacheSweepTargets());
    targets.addAll(_groupContainerCacheSweepTargets());
    targets.addAll(_handoffPasteboardTargets());

    return targets;
  }

  /// Port of `clean_support_app_data`: month-old CrashReporter files plus
  /// Messages preview/sticker caches. Message attachments themselves are
  /// never touched — only these three cache leaves.
  List<String> _supportAppDataTargets() => [
    ..._filesOlderThan(
      '$home/Library/Application Support/CrashReporter',
      const Duration(days: 30),
    ),
    ..._childrenOf('$home/Library/Messages/StickerCache'),
    ..._childrenOf('$home/Library/Messages/Caches/Previews/Attachments'),
    ..._childrenOf('$home/Library/Messages/Caches/Previews/StickerCache'),
  ];

  /// The curated allowlist of Apple-bundle sandboxed caches from
  /// `clean_app_caches`. These exist because [_containerCacheSweepTargets]
  /// protects every `com.apple.*` container by default — this is the
  /// reviewed set of exceptions, not a broader Apple sweep.
  List<String> _sandboxedAppleCacheTargets() {
    const roots = [
      'Containers/com.apple.wallpaper.agent/Data/Library/Caches',
      'Containers/com.apple.mediaanalysisd/Data/Library/Caches',
      'Containers/com.apple.mediaanalysisd/Data/tmp',
      'Containers/com.apple.AppStore/Data/Library/Caches',
      'Containers/com.apple.configurator.xpc.InternetService/Data/tmp',
      'Containers/com.apple.wallpaper.extension.aerials/Data/tmp',
      'Containers/com.apple.geod/Data/tmp',
      'Containers/com.apple.stocks/Data/Library/Caches',
      'Containers/com.apple.AvatarUI.AvatarPickerMemojiPicker/Data/Library/Caches',
      'Containers/com.apple.AMPArtworkAgent/Data/Library/Caches',
      'Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches',
      'Containers/com.apple.NeptuneOneExtension/Data/Library/Caches',
      'Containers/com.apple.AppleMediaServicesUI.UtilityExtension/Data/tmp',
    ];
    return [for (final root in roots) ..._childrenOf('$home/Library/$root')];
  }

  /// Port of `process_container_cache`: every non-critical, non-protected
  /// container's cache directory, one level deep. [isCriticalSystemComponent]
  /// and [shouldProtectData] decide which containers are even looked into;
  /// every surviving item is still re-checked by the funnel.
  List<String> _containerCacheSweepTargets() => [
    for (final container in _realDirectoriesOf('$home/Library/Containers'))
      if (!isCriticalSystemComponent(container.split('/').last) &&
          !shouldProtectData(container.split('/').last))
        ..._realDirChildren('$container/Data/Library/Caches'),
  ];

  /// Port of `clean_group_container_caches`. Apple's own group containers
  /// are skipped outright; a container whose id also owns a Safari Web
  /// Extension container is skipped so cleanup cannot trigger extension
  /// reinitialization. A protected owner still contributes its logs, just
  /// not its tmp/Caches.
  List<String> _groupContainerCacheSweepTargets() {
    final targets = <String>[];

    for (final container in _realDirectoriesOf(
      '$home/Library/Group Containers',
    )) {
      final id = container.split('/').last;
      if (id.startsWith('com.apple.') ||
          id.startsWith('group.com.apple.') ||
          id.startsWith('systemgroup.com.apple.')) {
        continue;
      }
      if (_hasSafariSibling(id)) continue;

      final normalizedId = id.startsWith('group.')
          ? id.substring('group.'.length)
          : id;
      final protected =
          shouldProtectData(id) || shouldProtectData(normalizedId);

      final candidates = [
        '$container/Logs',
        '$container/Library/Logs',
        if (!protected) '$container/tmp',
        if (!protected) '$container/Library/tmp',
        if (!protected) '$container/Caches',
        if (!protected) '$container/Library/Caches',
      ];
      for (final candidate in candidates) {
        targets.addAll(_realDirChildren(candidate));
      }
    }

    return targets;
  }

  /// A sibling `~/Library/Containers/<id>` holding anything matching
  /// `*Safari*` or `*safari*` marks [id]'s group container as belonging to a
  /// Safari Web Extension.
  bool _hasSafariSibling(String id) {
    for (final child in _childrenOf('$home/Library/Containers/$id')) {
      final name = child.split('/').last;
      if (name.contains('Safari') || name.contains('safari')) return true;
    }
    return false;
  }

  /// Port of `clean_handoff_pasteboard_cache`: entries older than an hour in
  /// the Universal Clipboard staging directory.
  List<String> _handoffPasteboardTargets() {
    const pasteboard =
        'Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard';
    final dir = '$home/$pasteboard';
    if (!_isRealDirectory(dir)) return const [];

    final cutoff = DateTime.now().subtract(const Duration(minutes: 60));
    final targets = <String>[];
    try {
      for (final entity in _directory(dir).listSync(followLinks: false)) {
        if (entity is Link) continue;
        if (entity.statSync().modified.isBefore(cutoff)) {
          targets.add(entity.path);
        }
      }
    } on FileSystemException {
      // Unreadable is not "empty" anywhere else in this class either; the
      // pasteboard cache is simply left alone for this run.
    }
    return targets;
  }

  /// Files under [root], at most 5 directories deep, last modified more
  /// than [age] ago. Port of `safe_find_delete "$root" "*" ... "f"`.
  List<String> _filesOlderThan(String root, Duration age, {int maxDepth = 5}) {
    if (!_isRealDirectory(root)) return const [];
    final cutoff = DateTime.now().subtract(age);
    final targets = <String>[];

    void walk(String dir, int depth) {
      if (depth > maxDepth) return;
      List<FileSystemEntity> entries;
      try {
        entries = _directory(dir).listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final entity in entries) {
        if (entity is Directory) {
          walk(entity.path, depth + 1);
        } else if (entity is File &&
            entity.statSync().modified.isBefore(cutoff)) {
          targets.add(entity.path);
        }
      }
    }

    walk(root, 1);
    return targets..sort();
  }

  /// Everything Mole's `clean_browsers` proposes that is neither gated on
  /// the browser not currently running, nor genuinely redundant with the
  /// blanket `~/Library/Caches/*` sweep in [userEssentials].
  ///
  /// That sweep reaches a browser's own top-level cache directory (Chrome,
  /// Chromium, Arc, Dia, Brave, Yandex, Helium, Opera, Vivaldi, Comet,
  /// Orion, Zen, QQ Browser) whole, so repeating it here would only
  /// double-count its size. Safari and Edge are the exceptions: their
  /// bundle ids (`com.apple.Safari`, `com.microsoft.edgemac`) trip
  /// [shouldProtectPath]'s blanket vendor rule as top-level Caches
  /// children, so [userEssentials] always keeps rather than cleans them —
  /// their children are reached here instead, exactly as Mole does. Helium
  /// and Yandex's profile-level GPU/shader caches are neither
  /// process-guarded nor redundant, so they belong here too.
  ///
  /// The process-guarded profile caches for Chrome, Arc, Dia, Brave,
  /// Vivaldi and Firefox live in [BrowserProfileCachesLocalDataSource]
  /// instead, sharing this same section name — that one needs
  /// [ProcessGuard], which this pure-filesystem class deliberately does
  /// not depend on.
  ///
  /// Not ported: the Chrome/Edge/Brave old-version pruners
  /// (`clean_chrome_old_versions` and siblings) — version-comparison logic
  /// with its own evidence chain, deliberately left for a focused pass of
  /// its own.
  List<String> _browsersTargets() => [
    ..._childrenOf('$home/Library/Caches/com.apple.Safari'),
    ..._childrenOf('$home/Library/Caches/com.microsoft.edgemac'),
    ..._childrenOf('$home/.cache/puppeteer'),
    ..._serviceWorkerCacheTargets(),
    for (final profile in _realDirectoriesOf(
      '$home/Library/Application Support/net.imput.helium',
    ))
      for (final leaf in ['GPUCache', 'Application Cache'])
        ..._childrenOf('$profile/$leaf'),
    for (final leaf in [
      'component_crx_cache',
      'extensions_crx_cache',
      'GrShaderCache',
      'GraphiteDawnCache',
      'ShaderCache',
    ])
      ..._childrenOf(
        '$home/Library/Application Support/net.imput.helium/$leaf',
      ),
    for (final profile in _realDirectoriesOf(
      '$home/Library/Application Support/Yandex/YandexBrowser',
    ))
      ..._childrenOf('$profile/GPUCache'),
    for (final leaf in ['ShaderCache', 'GrShaderCache', 'GraphiteDawnCache'])
      ..._childrenOf(
        '$home/Library/Application Support/Yandex/YandexBrowser/$leaf',
      ),
  ];

  /// Port of the unguarded `clean_service_worker_cache` calls in
  /// `clean_browsers`: Service Worker cache storage is origin-keyed and safe
  /// to clean live, unlike the disk-backed caches above. A directory whose
  /// name looks like one of [_protectedServiceWorkerDomains] is left alone
  /// so an offline-capable PWA does not lose its registered worker.
  List<String> _serviceWorkerCacheTargets() {
    const profileRoots = [
      'Application Support/Google/Chrome',
      'Application Support/Arc',
      'Application Support/Arc/User Data',
      'Application Support/Dia/User Data',
      'Application Support/BraveSoftware/Brave-Browser',
      'Application Support/Vivaldi',
    ];
    final targets = <String>[];
    for (final root in profileRoots) {
      for (final profile in _realDirectoriesOf('$home/Library/$root')) {
        targets.addAll(
          _serviceWorkerCandidatesUnder('$profile/Service Worker/CacheStorage'),
        );
      }
    }
    return targets;
  }

  /// Directories exactly two levels below [cacheStorageDir]. Port of
  /// `find "$cache_path" -type d -depth 2`.
  List<String> _serviceWorkerCandidatesUnder(String cacheStorageDir) {
    if (!_isRealDirectory(cacheStorageDir)) return const [];
    final targets = <String>[];
    for (final level1 in _realDirectoriesOf(cacheStorageDir)) {
      for (final level2 in _realDirectoriesOf(level1)) {
        final domain = _domainLikeSegment
            .firstMatch(level2.split('/').last)
            ?.group(0);
        final protected =
            domain != null &&
            _protectedServiceWorkerDomains.any(domain.contains);
        if (!protected) targets.add(level2);
      }
    }
    return targets;
  }

  static final _domainLikeSegment = RegExp(
    r'[a-zA-Z0-9][-a-zA-Z0-9]*\.[a-zA-Z]{2,}',
  );

  /// Port of `PROTECTED_SW_DOMAINS` in `bin/clean.sh`: web editors, Google
  /// Workspace, code platforms and collaboration tools whose offline/PWA
  /// mode depends on a registered service worker.
  static const _protectedServiceWorkerDomains = [
    'capcut.com',
    'photopea.com',
    'pixlr.com',
    'docs.google.com',
    'sheets.google.com',
    'slides.google.com',
    'drive.google.com',
    'mail.google.com',
    'github.com',
    'gitlab.com',
    'codepen.io',
    'codesandbox.io',
    'replit.com',
    'stackblitz.com',
    'notion.so',
    'figma.com',
    'linear.app',
    'excalidraw.com',
  ];

  /// Port of the guard-free slice of `clean_cloud_storage` plus all of
  /// `clean_office_applications`.
  ///
  /// Dropbox, Google Drive and OneDrive are gated on the sync client not
  /// currently running in Mole; hoopix has no process-liveness check yet,
  /// so all three are left out. Baidu Netdisk and Alibaba Cloud are left
  /// out too, but for the opposite reason: verified not blanket-protected,
  /// so [userEssentials] already sweeps their top-level Caches directory
  /// whole. Box, and every Office/Mail/Thunderbird target below, *are*
  /// blanket-protected as `com.apple.*` / `com.microsoft.*` / vendor
  /// bundle ids — [userEssentials] can only ever keep them, never clean
  /// them, so they are reached here instead, exactly as Mole does.
  List<String> _cloudAndOfficeTargets() {
    final targets = <String>[
      '$home/Library/Caches/com.box.desktop',
      '$home/Library/Caches/com.microsoft.Word',
      '$home/Library/Caches/com.microsoft.Excel',
      '$home/Library/Caches/com.microsoft.Powerpoint',
    ];

    for (final app in ['Word', 'Excel']) {
      final container = '$home/Library/Containers/com.microsoft.$app/Data';
      targets.addAll(_childrenOf('$container/Library/Caches'));
      targets.addAll(_childrenOf('$container/tmp'));
      targets.addAll(_childrenOf('$container/Library/Logs'));
    }

    targets.addAll(_childrenOf('$home/Library/Caches/com.microsoft.Outlook'));
    for (final child in _childrenOf('$home/Library/Caches')) {
      if (child.split('/').last.startsWith('com.apple.iWork.')) {
        targets.add(child);
      }
    }
    targets.addAll(_childrenOf('$home/Library/Caches/org.mozilla.thunderbird'));
    targets.addAll(_childrenOf('$home/Library/Caches/com.apple.mail'));

    return targets;
  }

  /// Port of the guard-free slice of `clean_virtualization_tools`.
  ///
  /// VMware Fusion's bundle id is blanket-protected as a top-level Caches
  /// directory (`com.vmware.*`), so it is repeated here; Parallels
  /// (`com.parallels.*`) and Lima are not, so [userEssentials] already
  /// sweeps them whole and repeating them here would double-count their
  /// size.
  ///
  /// UTM's one non-redundant target is process-guarded and ported
  /// separately, in `UtmCachesLocalDataSource`.
  ///
  /// Not ported: Tart additionally reclaims its cache by running
  /// `tart prune`, not a Trash move — the same owner-command mechanism
  /// Developer tools uses — but that command is itself process-guarded
  /// against a live `tart` invocation, which this codebase has no check
  /// for yet.
  List<String> _virtualizationTargets() => [
    '$home/Library/Caches/com.vmware.fusion',
    '$home/VirtualBox VMs/.cache',
    ..._childrenOf('$home/.vagrant.d/tmp'),
  ];

  /// Port of `clean_application_support_logs`: a generic sweep over every
  /// `~/Library/Application Support/<app>` directory, but only ever into a
  /// fixed, known-regenerable set of Electron/Chromium-shaped cache
  /// subdirectory names — never the app's data as a whole. `Cache` and
  /// `CachedData` are only eligible when the app also has one of the other
  /// marker directories, which is what tells an arbitrary app's ambiguous
  /// "Cache" folder apart from a disk cache Mole can prove is regenerable.
  ///
  /// [isCriticalSystemComponent] and [shouldProtectData] gate which app
  /// directories are even looked into, exactly as the generic per-container
  /// sweep in [_containerCacheSweepTargets] does for `~/Library/Containers`
  /// — deep candidate paths here end in a fixed leaf name (`Code Cache`,
  /// `blob`, ...), never the app's own name, so the funnel's per-candidate
  /// [shouldProtectPath] check alone could not otherwise rule them out.
  List<String> _applicationSupportTargets() {
    final targets = <String>[];

    for (final appDir in _realDirectoriesOf(
      '$home/Library/Application Support',
    )) {
      final appName = appDir.split('/').last;
      if (isCriticalSystemComponent(appName)) continue;
      final protectedByName =
          shouldProtectData(appName) ||
          shouldProtectData(appName.toLowerCase());
      if (protectedByName) continue;
      if (shouldProtectPath(appDir, home: home)) continue;

      const alwaysEligible = [
        'Code Cache',
        'GPUCache',
        'DawnCache',
        'GrShaderCache',
        'GraphiteDawnCache',
        'DawnGraphiteCache',
        'DawnWebGPUCache',
        'Crashpad/completed',
      ];
      for (final leaf in alwaysEligible) {
        targets.addAll(_childrenOf('$appDir/$leaf'));
      }
      if (_hasRegenerableCacheMarkers(appDir)) {
        targets.addAll(_childrenOf('$appDir/Cache'));
        targets.addAll(_childrenOf('$appDir/CachedData'));
      }
    }

    // Group Containers logs, explicit allowlist.
    const groupContainerPath =
        'Library/Group Containers/group.com.apple.contentdelivery';
    targets.addAll(_childrenOf('$home/$groupContainerPath/Logs'));
    targets.addAll(_childrenOf('$home/$groupContainerPath/Library/Logs'));

    return targets;
  }

  bool _hasRegenerableCacheMarkers(String appDir) =>
      [
        'Code Cache',
        'GPUCache',
        'DawnCache',
        'GrShaderCache',
        'GraphiteDawnCache',
        'DawnGraphiteCache',
        'DawnWebGPUCache',
        'Crashpad',
      ].any(
        (marker) =>
            FileSystemEntity.typeSync('$appDir/$marker', followLinks: false) !=
            FileSystemEntityType.notFound,
      );

  /// Port of `clean_cached_device_firmware`: downloaded `.ipsw` restore
  /// images for iOS/iPadOS/iPod devices, re-downloadable on the next
  /// restore. iTunes' three per-device-kind folders are a direct listing;
  /// Apple Configurator nests firmware under a per-team-id group container,
  /// so every `*.group.com.apple.configurator` container is scanned in
  /// full rather than just its top level.
  List<String> _deviceFirmwareTargets() {
    final targets = <String>[];

    for (final kind in ['iPhone', 'iPad', 'iPod']) {
      targets.addAll(
        _ipswFilesIn('$home/Library/iTunes/$kind Software Updates'),
      );
    }

    for (final container in _realDirectoriesOf(
      '$home/Library/Group Containers',
    )) {
      if (container.split('/').last.endsWith('.group.com.apple.configurator')) {
        targets.addAll(_ipswFilesUnder(container));
      }
    }

    return targets;
  }

  List<String> _ipswFilesIn(String dir) => [
    for (final child in _childrenOf(dir))
      if (child.endsWith('.ipsw')) child,
  ];

  List<String> _ipswFilesUnder(String root, {int maxDepth = 6}) {
    final targets = <String>[];
    void walk(String dir, int depth) {
      if (depth > maxDepth) return;
      List<FileSystemEntity> entries;
      try {
        entries = _directory(dir).listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final entity in entries) {
        if (entity is Directory) {
          walk(entity.path, depth + 1);
        } else if (entity is File && entity.path.endsWith('.ipsw')) {
          targets.add(entity.path);
        }
      }
    }

    walk(root, 1);
    return targets..sort();
  }

  /// Immediate children of [path], or nothing when it cannot be listed.
  /// Symlinks are listed but never followed, so a link cannot redirect the
  /// sweep somewhere it was not pointed.
  List<String> _childrenOf(String path) {
    try {
      return [
        for (final entity in _directory(path).listSync(followLinks: false))
          entity.path,
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }

  /// Immediate real (non-symlink) subdirectories of [path]. Used where a
  /// symlinked container or candidate must be skipped entirely rather than
  /// listed as a target in its own right — Mole never descends into one to
  /// decide what else to propose.
  List<String> _realDirectoriesOf(String path) {
    try {
      return [
        for (final entity in _directory(path).listSync(followLinks: false))
          if (entity is Directory) entity.path,
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }

  /// Children of [path], but only when [path] itself is a real directory.
  /// A symlinked cache/tmp/Logs candidate is skipped rather than followed.
  List<String> _realDirChildren(String path) =>
      _isRealDirectory(path) ? _childrenOf(path) : const [];

  bool _isRealDirectory(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;
}
