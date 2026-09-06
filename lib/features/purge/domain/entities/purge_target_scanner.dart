import 'dart:io';

import 'package:hoopix/features/purge/domain/entities/cachedir_tag.dart';
import 'package:hoopix/features/purge/domain/entities/purge_constants.dart';

/// Ports the directory-walking half of `scan_purge_targets`
/// (`lib/clean/project.sh`): every directory between [minDepth] and
/// [maxDepth] levels below [root] whose basename is a [purgeTargets] entry,
/// or which itself carries a `CACHEDIR.TAG`.
///
/// Scanning does not stop at a match — Mole's own `fd`/`find` pass does
/// not prune there either, which is exactly why `filterNestedArtifacts`
/// exists: a `dist/` nested inside a matched `build/` inside a matched
/// `node_modules/` is still found, and collapsed into its outermost
/// ancestor afterward, not by pruning the scan early. [excludedFromDescent]
/// mirrors `fd`'s own fixed exclusion set — these are never entered, at
/// any depth, matched or not.
class PurgeTargetScanner {
  PurgeTargetScanner({
    Directory Function(String path)? directory,
    this.minDepth = 1,
    this.maxDepth = 6,
  }) : _directory = directory ?? Directory.new;

  final Directory Function(String path) _directory;
  final int minDepth;
  final int maxDepth;

  static const excludedFromDescent = {
    '.git',
    'Library',
    '.Trash',
    'Applications',
  };

  List<String> scan(String root) {
    final found = <String>[];

    void walk(String dir, int depth) {
      if (depth > maxDepth) return;

      final List<FileSystemEntity> entries;
      try {
        entries = _directory(dir).listSync(followLinks: false);
      } on FileSystemException {
        return;
      }

      for (final entity in entries) {
        if (entity is! Directory) continue;
        final name = entity.path.split('/').last;
        if (excludedFromDescent.contains(name)) continue;

        if (depth >= minDepth &&
            (purgeTargets.contains(name) || hasCachedirTag(entity.path))) {
          found.add(entity.path);
        }

        if (depth < maxDepth) walk(entity.path, depth + 1);
      }
    }

    walk(root, 1);
    return found;
  }
}
