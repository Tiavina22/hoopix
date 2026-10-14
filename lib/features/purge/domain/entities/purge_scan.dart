import 'package:hoopix/features/purge/domain/entities/nested_artifacts.dart';
import 'package:hoopix/features/purge/domain/entities/purge_protection.dart';
import 'package:hoopix/features/purge/domain/entities/purge_safety.dart';
import 'package:hoopix/features/purge/domain/entities/purge_target_scanner.dart';

/// Every purge candidate under [roots], mapped to the root it was found
/// under — the root is what `isSafeProjectArtifact` is checked against
/// again right before deletion.
///
/// Per root, in Mole's `process_scan_results` order: the walk's matches
/// are collapsed to their outermost artifact first, then each survivor
/// must be a safe artifact of that root and not a protected one. A root
/// whose walk ran out of time contributes nothing. A path two overlapping
/// roots both reach keeps the first root, and the whole set is collapsed
/// once more so an artifact never survives beside its own ancestor.
///
/// Pure filesystem reads, with no channel or process: the repository runs
/// it on a background isolate, so a large tree cannot freeze the window.
Map<String, String> findPurgeArtifacts(
  List<String> roots,
  PurgeTargetScanner scanner,
) {
  final foundUnderRoot = <String, String>{};
  for (final root in roots) {
    final matches = scanner.scan(root);
    if (matches == null) continue;
    for (final path in filterNestedArtifacts(matches)) {
      if (foundUnderRoot.containsKey(path)) continue;
      if (!isSafeProjectArtifact(path, root)) continue;
      if (isProtectedPurgeArtifact(path)) continue;
      foundUnderRoot[path] = root;
    }
  }
  return {
    for (final path in filterNestedArtifacts(foundUnderRoot.keys.toList()))
      path: foundUnderRoot[path]!,
  };
}
