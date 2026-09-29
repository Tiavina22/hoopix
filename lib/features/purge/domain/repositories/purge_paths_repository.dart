/// Where the user's own list of Purge scan folders is kept.
abstract class PurgePathsRepository {
  /// The file's location for display, with `~` for the home directory.
  String get displayPath;

  /// The file's raw lines, or null when there is no file.
  Future<List<String>?> read();

  /// Replaces the file with [lines].
  Future<void> save(List<String> lines);

  /// The folders automatic discovery finds right now.
  Future<List<String>> discover();

  /// Whether [path] is an existing folder, to flag one that is not.
  bool folderExists(String path);
}
