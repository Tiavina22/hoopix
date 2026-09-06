import 'dart:io';

import 'package:hoopix/core/platform/size_probe.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/purge/data/datasources/purge_identity.dart';
import 'package:hoopix/features/purge/domain/entities/nested_artifacts.dart';
import 'package:hoopix/features/purge/domain/entities/purge_activity.dart';
import 'package:hoopix/features/purge/domain/entities/purge_cloud_sync.dart';
import 'package:hoopix/features/purge/domain/entities/purge_discovery.dart';
import 'package:hoopix/features/purge/domain/entities/purge_plan.dart';
import 'package:hoopix/features/purge/domain/entities/purge_protection.dart';
import 'package:hoopix/features/purge/domain/entities/purge_safety.dart';
import 'package:hoopix/features/purge/domain/entities/purge_target_scanner.dart';
import 'package:hoopix/features/purge/domain/repositories/purge_repository.dart';

/// Sizing a project artifact is the same `du` work Clean's own caches do,
/// and a `node_modules` tree takes just as long to walk.
const _sizeTimeout = Duration(seconds: 60);

class PurgeRepositoryImpl implements PurgeRepository {
  PurgeRepositoryImpl({
    required this.home,
    PurgeDiscovery? discovery,
    PurgeTargetScanner? scanner,
    PurgeActivityClassifier? activityClassifier,
    PurgeIdentity? identity,
    SizeProbe? sizeProbe,
    Directory Function(String path)? directory,
  }) : _discovery = discovery ?? PurgeDiscovery(home: home),
       _scanner = scanner ?? PurgeTargetScanner(),
       _activityClassifier = activityClassifier ?? PurgeActivityClassifier(),
       _identity = identity ?? PurgeIdentity(),
       _sizeProbe =
           sizeProbe ?? const SizeProbe(ProcessRunner(timeout: _sizeTimeout)),
       _directory = directory ?? Directory.new;

  final String home;
  final PurgeDiscovery _discovery;
  final PurgeTargetScanner _scanner;
  final PurgeActivityClassifier _activityClassifier;
  final PurgeIdentity _identity;
  final SizeProbe _sizeProbe;
  final Directory Function(String path) _directory;

  @override
  Stream<PurgePlan> watchPlan() async* {
    // path -> the root it was found under, needed to re-run
    // isSafeProjectArtifact against the same root right before deletion.
    final foundUnderRoot = <String, String>{};
    for (final root in _discovery.discover()) {
      for (final found in _scanner.scan(root)) {
        if (foundUnderRoot.containsKey(found)) continue;
        if (!isSafeProjectArtifact(found, root)) continue;
        if (isProtectedPurgeArtifact(found)) continue;
        foundUnderRoot[found] = root;
      }
    }

    final collapsed = filterNestedArtifacts(foundUnderRoot.keys.toList());

    final candidates = <PurgeCandidate>[];
    for (final path in collapsed) {
      final identitySnapshot = await _identity.snapshot(path);
      // Gone, or unreadable, before its own identity could be pinned:
      // never propose what cannot be safely re-verified later.
      if (!identitySnapshot.isComplete) continue;

      candidates.add(
        PurgeCandidate(
          path: path,
          searchRoot: foundUnderRoot[path]!,
          activity: _activityClassifier.classify(path),
          isCloudSynced: isCloudSyncedPurgePath(path, home: home),
          identityAtScan: identitySnapshot,
        ),
      );
    }

    // Every row is named and grouped before any measuring, so the preview
    // is readable immediately — the same reason Clean's own plan does this.
    yield PurgePlan(candidates: candidates);
    if (candidates.isEmpty) return;

    var sizes = {for (final c in candidates) c.path: c.sizeBytes};
    await for (final probe in SizeProbe.pool([
      for (final c in candidates) c.path,
    ], _sizeProbe.sizeOf)) {
      sizes = {...sizes, probe.key: probe.sizeBytes};
      yield PurgePlan(
        candidates: [for (final c in candidates) c.withSize(sizes[c.path])],
      );
    }
  }

  @override
  Future<Map<String, String>> approve(List<PurgeCandidate> approved) async {
    final failures = <String, String>{};

    for (final candidate in approved) {
      final failure = await _revalidationFailure(candidate);
      if (failure != null) {
        failures[candidate.path] = failure;
        continue;
      }

      try {
        await _directory(candidate.path).delete(recursive: true);
      } on FileSystemException catch (error) {
        failures[candidate.path] = error.message;
      }
    }

    return failures;
  }

  /// Null when [candidate] is still exactly what the scan found and still
  /// eligible; otherwise a failure message. Every check Mole re-runs
  /// immediately before its own `safe_remove` call, run again here right
  /// before the actual delete — the plan was built, then the user read it,
  /// and either step can take long enough for the filesystem to change
  /// underneath.
  Future<String?> _revalidationFailure(PurgeCandidate candidate) async {
    final type = FileSystemEntity.typeSync(candidate.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return 'no longer exists';
    if (type == FileSystemEntityType.link) return 'is now a symlink';
    if (type != FileSystemEntityType.directory) {
      return 'is no longer a directory';
    }

    if (!isSafeProjectArtifact(candidate.path, candidate.searchRoot)) {
      return 'no longer a safe purge target';
    }
    if (isProtectedPurgeArtifact(candidate.path)) return 'now protected';
    if (!await _identity.matches(candidate.path, candidate.identityAtScan)) {
      return 'changed since scan';
    }
    return null;
  }
}
