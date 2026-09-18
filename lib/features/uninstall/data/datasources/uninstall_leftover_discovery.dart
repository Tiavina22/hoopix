import 'dart:io';

import 'package:hoopix/features/uninstall/domain/entities/launch_agent_match.dart';
import 'package:hoopix/features/uninstall/domain/entities/uninstall_leftover_paths.dart';

/// Filters [uninstallLeftoverPathCandidates] by what actually exists on
/// disk — the candidate generator is pure and knows nothing about the
/// filesystem, matching `find_app_files`' own `[[ ! -e "$expanded_path" ]]
/// && continue` gate.
///
/// Also ports `find_app_files`' two user LaunchAgents scans, which are
/// directory listings rather than fixed templates: the bundle-id helper
/// plists ([launchAgentNameMatchesBundleId]) and the name-based glob
/// ([launchAgentNameMatchesAppName]). Unloading those jobs before their
/// plists move is [LaunchServiceTeardown]'s job, not this one's.
class UninstallLeftoverDiscovery {
  UninstallLeftoverDiscovery({
    FileSystemEntityType Function(String path)? typeOf,
    List<String> Function(String directory)? listNames,
  }) : _typeOf =
           typeOf ??
           ((path) => FileSystemEntity.typeSync(path, followLinks: false)),
       _listNames = listNames ?? listDirectoryNames;

  final FileSystemEntityType Function(String path) _typeOf;
  final List<String> Function(String directory) _listNames;

  List<String> discover({
    required String home,
    required String bundleId,
    required String appName,
  }) {
    final candidates = uninstallLeftoverPathCandidates(
      home: home,
      bundleId: bundleId,
      appName: appName,
    );

    final found = [
      for (final path in candidates)
        if (_typeOf(path) != FileSystemEntityType.notFound) path,
    ];

    final agentsDir = '$home/Library/LaunchAgents';
    for (final name in _listNames(agentsDir)) {
      if (!launchAgentNameMatchesBundleId(name, bundleId) &&
          !launchAgentNameMatchesAppName(name, appName)) {
        continue;
      }
      final path = '$agentsDir/$name';
      if (!found.contains(path)) found.add(path);
    }

    return found;
  }
}

/// Every entry name directly inside [directory] (`find -maxdepth 1`), or
/// nothing when it is missing or unreadable — the same "no directory, no
/// candidates" outcome as Mole's own `[[ -d ~/Library/LaunchAgents ]]`
/// gate.
List<String> listDirectoryNames(String directory) {
  try {
    return [
      for (final entity in Directory(directory).listSync(followLinks: false))
        entity.path.substring(entity.path.lastIndexOf('/') + 1),
    ];
  } on FileSystemException {
    return const [];
  }
}
