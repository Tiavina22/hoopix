import 'dart:io';

import 'package:hoopix/features/purge/domain/entities/purge_constants.dart';
import 'package:hoopix/features/purge/domain/entities/purge_container.dart';

/// Ports `discover_project_dirs` (`lib/clean/project.sh`): the roots purge
/// scans when the user has not configured any — every existing
/// [purgeDefaultSearchPaths] entry, plus every direct child of [home] that
/// [isProjectContainer] accepts.
///
/// Not ported: Mole's `mole_purge_resolve_path_case` dedup for
/// case-insensitive APFS (`~/Code` vs `~/code` naming the same directory,
/// issue #1416) — a real edge case, but one that needs shelling out to
/// `/bin/pwd -P` to read the true on-disk casing (Dart's own symlink
/// resolution does not reliably correct case on macOS). Left as a known
/// simplification rather than a silent gap: a user hitting this would see
/// one directory discovered twice, not anything deleted twice, since
/// discovery only proposes scan roots.
class PurgeDiscovery {
  PurgeDiscovery({required this.home, Directory Function(String path)? directory})
    : _directory = directory ?? Directory.new;

  final String home;
  final Directory Function(String path) _directory;

  List<String> discover() {
    final discovered = <String>{};

    for (final path in purgeDefaultSearchPaths(home)) {
      if (_exists(path)) discovered.add(path);
    }

    var homeEntries = const <FileSystemEntity>[];
    try {
      homeEntries = _directory(home).listSync(followLinks: false);
    } on FileSystemException {
      // Missing or unreadable $HOME: default search paths already checked
      // above are all discovery can offer.
    }

    for (final entity in homeEntries) {
      if (entity is! Directory) continue;
      if (discovered.contains(entity.path)) continue;
      if (isProjectContainer(entity.path, directory: _directory)) {
        discovered.add(entity.path);
      }
    }

    return discovered.toList()..sort();
  }

  bool _exists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;
}
