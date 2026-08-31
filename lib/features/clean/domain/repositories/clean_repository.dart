import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';

abstract class CleanRepository {
  /// Works out what a clean run would remove, and emits the plan as it
  /// fills in: the list of candidates first, then each size as it lands, so
  /// a slow directory does not hold up the whole preview.
  ///
  /// Nothing is removed. The plan is what the user approves or does not.
  Stream<CleanPlan> watchPlan();

  /// Moves the approved paths to the Trash, from where the user can put them
  /// back. Returns the ones that did not go, mapped to why.
  ///
  /// The plan already filtered these, but the native side checks its own
  /// protected-path rules again immediately before each move: the two checks
  /// are separated by the user reading a preview, and a path can change in
  /// between.
  Future<Map<String, String>> approve(List<CleanCandidate> approved);
}
