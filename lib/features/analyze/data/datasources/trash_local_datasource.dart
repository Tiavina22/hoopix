import 'package:hoopix/core/platform/trash.dart';

class TrashLocalDataSource {
  const TrashLocalDataSource([this._trash = const Trash()]);

  final Trash _trash;

  /// Paths that could not be moved, mapped to why. Empty means all of them
  /// reached the Trash.
  Future<Map<String, String>> moveToTrash(List<String> paths) =>
      _trash.moveToTrash(paths);
}
