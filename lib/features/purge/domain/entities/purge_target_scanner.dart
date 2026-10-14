import 'dart:io';

import 'package:hoopix/features/purge/domain/entities/cachedir_tag.dart';
import 'package:hoopix/features/purge/domain/entities/purge_constants.dart';

/// Ports the directory-walking half of `scan_purge_targets`
/// (`lib/clean/project.sh`): every directory between [minDepth] and
/// [maxDepth] levels below [root] whose basename is a [purgeTargets] entry,
/// or which itself carries a `CACHEDIR.TAG`.
///
/// A match is reported and not entered, as Mole's `fd --prune` and
/// `find ... -print -prune` do: nothing inside a `node_modules` can be a
/// candidate of its own once the directory itself is one, and walking it
/// anyway turned one Purge scan into tens of thousands of directory reads.
/// [excludedFromDescent] mirrors Mole's fixed exclusion set — these are
/// never entered, at any depth, matched or not.
class PurgeTargetScanner {
  PurgeTargetScanner({
    Directory Function(String path)? directory,
    this.minDepth = 1,
    this.maxDepth = 6,
    this.timeout = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _directory = directory ?? Directory.new,
       _now = now ?? DateTime.now;

  final Directory Function(String path) _directory;
  final DateTime Function() _now;
  final int minDepth;
  final int maxDepth;

  /// Mole's per-root scan budget (`MO_PURGE_SCAN_TIMEOUT_SEC`).
  final Duration timeout;

  static const excludedFromDescent = {
    '.git',
    'Library',
    '.Trash',
    'Applications',
  };

  /// The matches under [root], or null when the walk ran past [timeout].
  /// A partial walk is never returned: Mole publishes a root's results only
  /// once every producer for it completed, so a timeout cannot turn a
  /// prefix of the tree into delete candidates.
  List<String>? scan(String root) {
    final deadline = _now().add(timeout);
    final found = <String>[];
    var timedOut = false;

    void walk(String dir, int depth) {
      if (timedOut || depth > maxDepth) return;
      if (_now().isAfter(deadline)) {
        timedOut = true;
        return;
      }

      final List<FileSystemEntity> entries;
      try {
        entries = _directory(dir).listSync(followLinks: false);
      } on FileSystemException {
        return;
      }

      for (final entity in entries) {
        if (timedOut) return;
        if (entity is! Directory) continue;
        final name = entity.path.split('/').last;
        if (excludedFromDescent.contains(name)) continue;

        if (depth >= minDepth &&
            (purgeTargets.contains(name) || hasCachedirTag(entity.path))) {
          found.add(entity.path);
          continue;
        }

        if (depth < maxDepth) walk(entity.path, depth + 1);
      }
    }

    walk(root, 1);
    return timedOut ? null : found;
  }
}
