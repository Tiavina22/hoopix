import 'dart:io';

import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Ports `clean_finder_metadata` / `clean_ds_store_tree` (`lib/clean/apps.sh`):
/// every `.DS_Store` file under the home directory, five levels deep.
/// Shares [CleanSectionsLocalDataSource.userEssentials]'s section name,
/// matching where Mole calls it — right alongside `clean_user_essentials`.
///
/// `.DS_Store` is Finder's own per-directory metadata cache, regenerated
/// silently the next time Finder visits that folder, so an exact-filename
/// match needs no age or size threshold the way most of this feature does.
///
/// The walk prunes exactly what Mole's own `find` excludes, so it never
/// even looks inside them: `Library/Application Support/MobileSync` (iOS
/// backups), `Library/Developer` (Xcode's own trees), `.Trash`,
/// `node_modules`, `.git`, and `Library/Caches` (already swept by
/// `userEssentials` itself). A match is checked against these by suffix,
/// the same way Mole's `-path "*/name"` does, so a nested `node_modules`
/// several levels down is pruned exactly as the top-level one is.
///
/// Not ported: Mole's `PROTECT_FINDER_METADATA` global on/off toggle. A
/// user who wants a `.DS_Store` left alone already has the general
/// whitelist file every other candidate here respects; a second,
/// feature-specific switch is not needed on top of it.
class FinderMetadataLocalDataSource {
  FinderMetadataLocalDataSource({
    required this.home,
    Directory Function(String path)? directory,
  }) : _directory = directory ?? Directory.new;

  final String home;
  final Directory Function(String path) _directory;

  static const _maxDepth = 5;

  static const _prunedSuffixes = [
    'Library/Application Support/MobileSync',
    'Library/Developer',
    '.Trash',
    'node_modules',
    '.git',
    'Library/Caches',
  ];

  CleanSectionTargets enumerate() {
    final targets = <String>[];
    void walk(String dir, int depth) {
      if (depth > _maxDepth) return;
      List<FileSystemEntity> entries;
      try {
        entries = _directory(dir).listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final entity in entries) {
        if (entity is Directory) {
          if (_isPruned(entity.path)) continue;
          walk(entity.path, depth + 1);
        } else if (entity is File && entity.path.endsWith('/.DS_Store')) {
          targets.add(entity.path);
        }
      }
    }

    walk(home, 1);
    return CleanSectionTargets(
      CleanSectionsLocalDataSource.userEssentials,
      targets..sort(),
    );
  }

  bool _isPruned(String path) =>
      _prunedSuffixes.any((suffix) => path.endsWith('/$suffix'));
}
