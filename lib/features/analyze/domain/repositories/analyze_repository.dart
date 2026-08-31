import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';

/// Abstract source of directory-listing data. A [Stream] rather than a
/// [Future] because a listing arrives progressively: the entries first, then
/// each directory's recursive size as it finishes computing.
abstract class AnalyzeRepository {
  /// The curated entry screen: structural roots plus the paths that quietly
  /// accumulate space. Not a directory listing.
  Stream<DirectoryScan> watchOverview();

  Stream<DirectoryScan> watchDirectory(String path);

  /// The biggest files under [root], answered from the Spotlight index
  /// rather than by walking the tree.
  Future<List<AnalyzeEntry>> findLargeFiles(String root);

  /// Opens the path in Finder. Non-destructive; returns false if Finder
  /// could not be asked (the caller surfaces that, it is never fatal).
  Future<bool> revealInFinder(String path);

  /// Moves [paths] to the Trash, from where the user can put them back.
  /// Returns the ones that were refused or failed, mapped to why; an empty
  /// map means all of them were moved.
  Future<Map<String, String>> moveToTrash(List<String> paths);

  /// Local Time Machine snapshot count, shown only on the overview. Null
  /// when the probe failed — nothing to report, not zero.
  Future<int?> localSnapshotCount();
}
