import 'dart:io';

import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Enumerates what Mole's `clean_user_gui_applications` proposes
/// (`lib/clean/app_caches.sh`) — one entry point covering roughly twenty
/// desktop-app categories, kept in its own class rather than growing
/// [CleanSectionsLocalDataSource] further, matching that file's own scale
/// in Mole.
///
/// A top-level `Library/Caches/<name>` target is repeated here only when
/// verified [shouldProtectPath]-blanket-protected as a whole directory
/// (`com.apple.*`, `com.microsoft.*`, and a handful of specific vendor
/// bundles this codebase also protects) — the same rule the App caches and
/// Browsers sections use. A target that is *not* blanket-protected is left
/// out: the `User essentials` section's top-level Caches sweep already
/// reaches it whole, so repeating it here would only double-count its
/// size. Every verdict below was checked against `shouldProtectPath`
/// directly rather than guessed. A `Containers/<id>/Data/Library/Caches`
/// target is left out for the same reason when its bundle id is not
/// blocked from the generic container sweep in the App caches section —
/// only a different subpath (`Data/tmp`, a nested Application Support
/// folder, ...) that sweep never looks at is repeated here.
///
/// Not ported: `clean_translation_apps` proposes only unprotected,
/// already-redundant top-level Caches targets, so it contributes nothing
/// and is omitted entirely. Autodesk (including old Fusion bundles) and
/// Simulator caches (which need an `xcrun simctl` liveness check this
/// codebase does not have) are process-guarded in Mole and still not
/// ported. Final Cut Pro generated caches now are, in
/// [FinalCutProGeneratedCachesLocalDataSource]; Xcode tooling is too, in
/// `XcodeCachesLocalDataSource`. Chrome/Edge/Brave-style old-version
/// pruning does not apply here.
class AppsAndUtilitiesLocalDataSource {
  AppsAndUtilitiesLocalDataSource({
    required this.home,
    Directory Function(String path)? directory,
  }) : _directory = directory ?? Directory.new;

  final String home;
  final Directory Function(String path) _directory;

  static const appsAndUtilities = 'Apps & utilities';

  CleanSectionTargets enumerate() => CleanSectionTargets(appsAndUtilities, [
    ..._communicationAppTargets(),
    ..._dingtalkTargets(),
    ..._aiAppTargets(),
    ..._designToolTargets(),
    ..._videoToolTargets(),
    ..._threeDToolTargets(),
    ..._productivityAppTargets(),
    ..._mediaPlayerTargets(),
    ..._videoPlayerTargets(),
    ..._downloadManagerTargets(),
    ..._gamingPlatformTargets(),
    ..._screenshotToolTargets(),
    ..._emailClientTargets(),
    ..._taskAppTargets(),
    ..._shellUtilTargets(),
    ..._systemUtilTargets(),
    ..._noteAppTargets(),
    ..._launcherAppTargets(),
    ..._remoteDesktopTargets(),
  ]);

  List<String> _communicationAppTargets() => [
    ..._childrenOf('$home/Library/Application Support/discord/Cache'),
    ..._childrenOf('$home/Library/Application Support/legcord/Cache'),
    ..._childrenOf('$home/Library/Application Support/Slack/Cache'),
    ..._childrenOf('$home/Library/Caches/us.zoom.xos'),
    ..._childrenOf('$home/Library/Caches/com.tencent.xinWeChat'),
    ..._childrenOf('$home/Library/Caches/ru.keepcoder.Telegram'),
    ..._childrenOf('$home/Library/Caches/com.microsoft.teams2'),
    ..._childrenOf('$home/Library/Caches/net.whatsapp.WhatsApp'),
    ..._childrenOf('$home/Library/Caches/com.skype.skype'),
    ..._childrenOf('$home/Library/Caches/com.tencent.qq'),
    for (final leaf in [
      'Cache',
      'Application Cache',
      'Code Cache',
      'GPUCache',
      'logs',
      'tmp',
    ])
      ..._childrenOf('$home/Library/Application Support/Microsoft/Teams/$leaf'),
  ];

  List<String> _dingtalkTargets() => [
    ..._childrenOf('$home/Library/Caches/com.alibaba.AliLang.osx'),
    ..._childrenOf('$home/Library/Application Support/iDingTalk/log'),
    ..._childrenOf('$home/Library/Application Support/iDingTalk/holmeslogs'),
  ];

  List<String> _aiAppTargets() => [
    ..._childrenOf('$home/Library/Caches/com.openai.chat'),
    ..._childrenOf('$home/Library/Caches/com.anthropic.claudefordesktop'),
    ..._childrenOf('$home/Library/Logs/Claude'),
    ..._childrenOf('$home/Library/Caches/com.lmstudio.lmstudio'),
    // Codex Desktop state is deliberately left intact — no target here,
    // matching Mole's own no-op branch.
  ];

  List<String> _designToolTargets() => [
    ..._childrenOf('$home/Library/Caches/com.bohemiancoding.sketch3'),
    ..._childrenOf(
      '$home/Library/Application Support/com.bohemiancoding.sketch3/cache',
    ),
    ..._cachesGrandchildrenMatching('com.adobe.'),
    ..._childrenOf('$home/Library/Caches/com.figma.Desktop'),
    ..._childrenOf(
      '$home/Library/Application Support/Adobe/Common/Media Cache Files',
    ),
  ];

  /// Final Cut Pro's and JianyingPro's *generated* caches are process-guarded
  /// in Mole and not ported; their plain top-level app caches below are not.
  List<String> _videoToolTargets() => [
    ..._childrenOf('$home/Library/Caches/net.telestream.screenflow10'),
    ..._childrenOf('$home/Library/Caches/com.apple.FinalCut'),
    ..._childrenOf('$home/Library/Caches/com.blackmagic-design.DaVinciResolve'),
    ..._childrenOf('$home/Movies/CacheClip'),
    ..._cachesGrandchildrenMatching('com.adobe.PremierePro.'),
  ];

  List<String> _threeDToolTargets() => [
    ..._childrenOf('$home/Library/Caches/com.maxon.cinema4d'),
  ];

  List<String> _productivityAppTargets() => [
    ..._childrenOf('$home/Library/Application Support/Quark/Cache/videoCache'),
    ..._childrenOf('$home/.cache/kaku'),
    ..._childrenOf('$home/Library/Application Support/spacedrive/thumbnails'),
    ..._childrenOf(
      '$home/Library/Containers/is.follow/Data/Library/Application Support/Folo/Cache/Cache_Data',
    ),
  ];

  List<String> _mediaPlayerTargets() => [
    ..._spotifyTargets(),
    '$home/Library/Caches/com.apple.Music',
    '$home/Library/Caches/com.apple.podcasts',
    ..._podcastsContainerTargets(),
    ..._childrenOf('$home/Library/Caches/com.apple.TV'),
    '$home/Library/Caches/tv.plex.player.desktop',
    '$home/Library/Caches/com.netease.163music',
    ..._qqMusicContainerTargets(),
  ];

  List<String> _spotifyTargets() {
    final storage =
        '$home/Library/Application Support/Spotify/PersistentCache/Storage';
    var hasOfflineMusic = false;
    final bnk = File('$storage/offline.bnk');
    if (bnk.existsSync()) {
      try {
        hasOfflineMusic = bnk.lengthSync() > 1024;
      } on FileSystemException {
        // Unreadable size is not evidence either way.
      }
    }
    if (!hasOfflineMusic && _isRealDirectory(storage)) {
      hasOfflineMusic = _containsFileEndingWith(storage, '.file');
    }
    if (hasOfflineMusic) return const [];
    return _childrenOf('$home/Library/Caches/com.spotify.client');
  }

  List<String> _podcastsContainerTargets() {
    final tmp = '$home/Library/Containers/com.apple.podcasts/Data/tmp';
    return [
      '$tmp/StreamedMedia',
      for (final child in _childrenOf(tmp))
        if (_isPodcastsTempArtifact(child.split('/').last)) child,
    ];
  }

  bool _isPodcastsTempArtifact(String name) =>
      name.endsWith('.heic') ||
      name.endsWith('.img') ||
      (name.contains('CFNetworkDownload') && name.endsWith('.tmp'));

  /// QQ Music Mac's container cache directory is not blanket-protected, so
  /// the App caches section's generic container sweep already reaches
  /// `Data/Library/Caches`; only its deeper, differently-named
  /// `Application Support/QQMusicMac` streaming/log/temp leaves are unique
  /// to this section.
  List<String> _qqMusicContainerTargets() {
    final container =
        '$home/Library/Containers/com.tencent.QQMusicMac'
        '/Data/Library/Application Support/QQMusicMac';
    return [
      ..._childrenOf('$container/iRRCache'),
      ..._childrenOf('$container/iLog'),
      ..._childrenOf('$container/iCache'),
      ..._childrenOf('$container/iTemp'),
    ];
  }

  List<String> _videoPlayerTargets() => [
    '$home/Library/Caches/com.colliderli.iina',
    '$home/Library/Caches/org.videolan.vlc',
    '$home/Library/Caches/io.mpv',
    for (final leaf in ['Upgrade', 'VideoNative', 'documentCache'])
      ..._childrenOf(
        '$home/Library/Containers/com.tencent.tenvideo/Data/Library/Application Support/$leaf',
      ),
    ..._childrenOf(
      '$home/Library/Containers/com.wuziqi.SenPlayer/Data/tmp/videoCache',
    ),
    ..._childrenOf(
      '$home/Library/Application Support/stremio/stremio-server/stremio-cache',
    ),
  ];

  List<String> _downloadManagerTargets() => [..._neatdmStaleSegmentTargets()];

  /// Port of `clean_neatdm_stale_segments`. History (`NeatDB.db`) is never
  /// touched — only numbered segment directories whose `seg.x0` marker is
  /// older than the shared 30-day orphan-age default, since a resumable
  /// download's URL has long since expired by then.
  List<String> _neatdmStaleSegmentTargets() {
    final neatdmDir =
        '$home/Library/Application Support/com.NeatDownloadManager';
    if (!_isRealDirectory(neatdmDir)) return const [];

    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final targets = <String>[];
    for (final child in _realDirectoriesOf(neatdmDir)) {
      final name = child.split('/').last;
      if (!RegExp(r'^[0-9]+$').hasMatch(name)) continue;
      final marker = File('$child/seg.x0');
      if (!marker.existsSync()) continue;
      try {
        if (marker.statSync().modified.isBefore(cutoff)) targets.add(child);
      } on FileSystemException {
        // An unreadable marker is not evidence of staleness.
      }
    }
    return targets;
  }

  List<String> _gamingPlatformTargets() => [
    for (final leaf in ['htmlcache', 'appcache', 'depotcache', 'logs'])
      ..._childrenOf('$home/Library/Application Support/Steam/$leaf'),
    ..._childrenOf(
      '$home/Library/Application Support/Steam/steamapps/shadercache',
    ),
    ..._childrenOf('$home/Library/Application Support/Battle.net/Cache'),
    for (final leaf in ['logs', 'crash-reports', 'webcache', 'webcache2'])
      ..._childrenOf('$home/Library/Application Support/minecraft/$leaf'),
    ..._childrenOf('$home/.lunarclient/game-cache'),
    ..._childrenOf('$home/.lunarclient/launcher-cache'),
    ..._childrenOf('$home/.lunarclient/logs'),
    for (final offlineDir in _realDirectoriesOf('$home/.lunarclient/offline'))
      ..._childrenOf('$offlineDir/logs'),
    for (final fileDir in _realDirectoriesOf(
      '$home/.lunarclient/offline/files',
    ))
      ..._childrenOf('$fileDir/logs'),
    ..._childrenOf('$home/Library/Application Support/PCSX2/cache'),
    ..._childrenOf('$home/Library/Logs/PCSX2'),
    ..._childrenOf('$home/Library/Application Support/rpcs3/logs'),
  ];

  List<String> _screenshotToolTargets() => [
    ..._cachesChildrenMatching('com.cleanshot.'),
    '$home/Library/Caches/com.reincubate.camo',
    '$home/Library/Caches/com.xnipapp.xnip',
  ];

  List<String> _emailClientTargets() => [
    '$home/Library/Caches/com.readdle.smartemail-Mac',
    ..._cachesChildrenMatching('com.airmail.'),
  ];

  List<String> _taskAppTargets() => [
    '$home/Library/Caches/com.todoist.mac.Todoist',
    ..._cachesChildrenMatching('com.any.do.'),
  ];

  List<String> _shellUtilTargets() => [
    for (final child in _childrenOf(home))
      if (child.split('/').last.startsWith('.zcompdump')) child,
    '$home/.lesshst',
    '$home/.viminfo.tmp',
    '$home/.wget-hsts',
    ..._childrenOf('$home/.cacher/logs'),
    ..._childrenOf('$home/.kite/logs'),
    ..._childrenOf('$home/Library/Caches/dev.warp.Warp-Stable'),
    '$home/Library/Logs/warp.log',
    // com.mitchellh.ghostty is not blanket-protected as a top-level Caches
    // directory, so userEssentials already sweeps it whole; repeating it
    // here (as Mole does with its own children-only target) would only
    // double-count its size.
  ];

  List<String> _systemUtilTargets() => [
    ..._childrenOf(
      '$home/Library/Application Support/WeType/com.onevcat.Kingfisher.ImageCache.WeType',
    ),
    ..._childrenOf('$home/Library/Application Support/WeType/DictUpdate'),
    for (final leaf in [
      'Cache',
      'Code Cache',
      'GPUCache',
      'DawnGraphiteCache',
      'DawnWebGPUCache',
      'logs',
    ])
      ..._childrenOf('$home/Library/Application Support/mihomo-party/$leaf'),
  ];

  List<String> _noteAppTargets() => [
    ..._childrenOf('$home/Library/Caches/notion.id'),
    ..._childrenOf('$home/Library/Caches/md.obsidian'),
    ..._cachesGrandchildrenMatching('com.bear-writer.'),
  ];

  List<String> _launcherAppTargets() => [
    ..._childrenOf('$home/Library/Caches/com.runningwithcrayons.Alfred'),
  ];

  // com.todesk.* and com.sunlogin.* are not blanket-protected as top-level
  // Caches directories, so userEssentials already sweeps them whole;
  // repeating them here would only double-count their size.
  List<String> _remoteDesktopTargets() => [
    ..._cachesGrandchildrenMatching('com.teamviewer.'),
    ..._cachesGrandchildrenMatching('com.anydesk.'),
  ];

  /// Whole top-level `~/Library/Caches` entries whose name starts with
  /// [prefix]. For a target Mole lists without a trailing `/*`.
  List<String> _cachesChildrenMatching(String prefix) => [
    for (final child in _childrenOf('$home/Library/Caches'))
      if (child.split('/').last.startsWith(prefix)) child,
  ];

  /// Children of every top-level `~/Library/Caches` entry whose name starts
  /// with [prefix]. For a target Mole lists as `<prefix>*/*`.
  List<String> _cachesGrandchildrenMatching(String prefix) => [
    for (final dir in _cachesChildrenMatching(prefix)) ..._childrenOf(dir),
  ];

  /// Whether any file anywhere under [root] has a name ending in [suffix].
  /// Stops at the first match, mirroring `find ... -name "*$suffix" | head -1`.
  bool _containsFileEndingWith(String root, String suffix, {int maxDepth = 8}) {
    var found = false;
    void walk(String dir, int depth) {
      if (found || depth > maxDepth) return;
      List<FileSystemEntity> entries;
      try {
        entries = _directory(dir).listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final entity in entries) {
        if (found) return;
        if (entity is Directory) {
          walk(entity.path, depth + 1);
        } else if (entity is File && entity.path.endsWith(suffix)) {
          found = true;
          return;
        }
      }
    }

    walk(root, 1);
    return found;
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

  /// Immediate real (non-symlink) subdirectories of [path].
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

  bool _isRealDirectory(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.directory;
}
