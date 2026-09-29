/// Where the user's cleanup whitelist is kept.
abstract class WhitelistRepository {
  /// The file's location for display, with `~` for the home directory.
  String get displayPath;

  /// The file's raw lines, or null when there is no file yet — which is
  /// what makes Clean apply the convenience defaults.
  Future<List<String>?> read();

  /// Replaces the file with [lines].
  Future<void> save(List<String> lines);
}
