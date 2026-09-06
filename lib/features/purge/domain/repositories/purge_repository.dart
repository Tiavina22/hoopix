import 'package:hoopix/features/purge/domain/entities/purge_plan.dart';

abstract class PurgeRepository {
  /// Works out what a purge run would remove, emitting the plan as it
  /// fills in: candidates first, then each size as it lands, the same
  /// progressive shape Clean's own plan uses.
  ///
  /// Nothing is removed. The plan is what the user approves or does not.
  Stream<PurgePlan> watchPlan();

  /// Permanently deletes each approved candidate — not Trash-routed,
  /// matching Mole's own `safe_remove` for this command: a project
  /// artifact is rebuildable, not something a user expects to recover from
  /// the Trash. Every candidate is revalidated (still a safe target, still
  /// not protected, identity unchanged since scan) immediately before its
  /// own deletion. Returns the paths that did not go, mapped to why.
  Future<Map<String, String>> approve(List<PurgeCandidate> approved);
}
