import 'dart:io';

import 'package:hoopix/features/purge/domain/entities/purge_constants.dart';

/// Ports `is_project_container` (`lib/clean/project.sh`): whether [dir] is
/// a directory purge discovery should look *inside* for projects, rather
/// than a project (or artifact) itself.
///
/// The [purgeTargets] check is the load-bearing rule here — see that
/// list's own doc for exactly what breaks if a target name is ever
/// accepted as a container. A path a user adds explicitly through purge's
/// own config file bypasses this function entirely (only auto-discovery
/// calls it), which is the documented escape hatch for a legitimately
/// target-named container.
bool isProjectContainer(
  String dir, {
  int maxDepth = 2,
  Directory Function(String path)? directory,
}) {
  final base = dir.split('/').last;
  if (base.startsWith('.')) return false;
  const reserved = {
    'Library',
    'Applications',
    'Movies',
    'Music',
    'Pictures',
    'Public',
  };
  if (reserved.contains(base)) return false;
  if (purgeTargets.contains(base)) return false;

  return _hasIndicatorWithin(
    dir,
    maxDepth: maxDepth,
    directory: directory ?? Directory.new,
  );
}

/// Whether any [projectIndicators] filename appears within [maxDepth]
/// levels below [dir] — [dir]'s direct children are depth 1, matching
/// `find "$dir" -maxdepth "$maxDepth"`'s own depth counting (the starting
/// directory itself is depth 0 there, but an indicator can never be the
/// scanned directory's own name, so that level contributes nothing).
bool _hasIndicatorWithin(
  String dir, {
  required int maxDepth,
  required Directory Function(String path) directory,
}) {
  bool walk(String current, int depth) {
    if (depth > maxDepth) return false;

    final List<FileSystemEntity> entries;
    try {
      entries = directory(current).listSync(followLinks: false);
    } on FileSystemException {
      return false;
    }

    for (final entity in entries) {
      if (projectIndicators.contains(entity.path.split('/').last)) {
        return true;
      }
    }

    if (depth < maxDepth) {
      for (final entity in entries) {
        if (entity is Directory && walk(entity.path, depth + 1)) {
          return true;
        }
      }
    }
    return false;
  }

  return walk(dir, 1);
}
