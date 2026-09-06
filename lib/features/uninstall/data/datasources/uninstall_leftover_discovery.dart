import 'dart:io';

import 'package:hoopix/features/uninstall/domain/entities/uninstall_leftover_paths.dart';

/// Filters [uninstallLeftoverPathCandidates] by what actually exists on
/// disk — the candidate generator is pure and knows nothing about the
/// filesystem, matching `find_app_files`' own `[[ ! -e "$expanded_path" ]]
/// && continue` gate.
class UninstallLeftoverDiscovery {
  UninstallLeftoverDiscovery({
    FileSystemEntityType Function(String path)? typeOf,
  }) : _typeOf =
           typeOf ??
           ((path) => FileSystemEntity.typeSync(path, followLinks: false));

  final FileSystemEntityType Function(String path) _typeOf;

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

    return [
      for (final path in candidates)
        if (_typeOf(path) != FileSystemEntityType.notFound) path,
    ];
  }
}
