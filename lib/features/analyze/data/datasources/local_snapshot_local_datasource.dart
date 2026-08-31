import 'package:hoopix/core/process/process_runner.dart';

/// One dated snapshot line from `tmutil`, e.g. `2026-03-14-091530`.
final _snapshotDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}-\d{6}$');

/// Counts local Time Machine snapshots, which quietly hold space that never
/// shows up as a file or folder anywhere in the listing — the overview says
/// so alongside the count, the same caveat Mole's analyzer shows.
class LocalSnapshotLocalDataSource {
  const LocalSnapshotLocalDataSource(this._processRunner);

  final ProcessRunner _processRunner;

  /// Null when the probe failed — nothing to report, not zero snapshots.
  Future<int?> count() async {
    final result = await _processRunner.run('/usr/bin/tmutil', const [
      'listlocalsnapshotdates',
      '/',
    ]);
    if (!result.isSuccess) return null;
    return _parseCount(result.stdout!);
  }

  /// Ignores `tmutil`'s localized heading line and counts only the
  /// documented `YYYY-MM-DD-HHMMSS` date rows.
  static int _parseCount(String output) {
    var count = 0;
    for (final line in output.split('\n')) {
      if (_snapshotDatePattern.hasMatch(line.trim())) count++;
    }
    return count;
  }
}
