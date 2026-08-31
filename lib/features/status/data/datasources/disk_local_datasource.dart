import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/models/disk_status_model.dart';

/// Mount point prefixes that are tooling internals rather than storage a
/// person manages. Xcode mounts one read-only volume per installed simulator
/// runtime; each is permanently ~98% full by design, so listing them buries
/// the real disks under permanent red rows.
const _skippedMountPrefixes = ['/Library/Developer/CoreSimulator/Volumes/'];

/// Mount points `df -k` reports that aren't real user-visible volumes.
const _skippedMountPoints = {
  '/System/Volumes/VM',
  '/System/Volumes/Preboot',
  '/System/Volumes/Update',
  '/System/Volumes/xarts',
  '/System/Volumes/iSCPreboot',
  '/System/Volumes/Hardware',
  '/System/Volumes/Data',
  '/dev',
};

class DiskLocalDataSource {
  const DiskLocalDataSource(this._processRunner);

  final ProcessRunner _processRunner;

  Future<List<DiskStatusModel>> fetch() async {
    final result = await _processRunner.run('df', const ['-k']);
    if (!result.isSuccess) {
      throw StateError('disk: ${result.failure}');
    }

    final disks = <DiskStatusModel>[];
    for (final line in result.stdout!.split('\n').skip(1)) {
      if (line.trim().isEmpty) continue;
      final disk = DiskStatusModel.tryParseRow(line);
      if (disk == null) continue;
      if (_skippedMountPoints.contains(disk.mountPoint)) continue;
      if (_skippedMountPrefixes.any(disk.mountPoint.startsWith)) continue;
      disks.add(disk);
    }
    return disks;
  }
}
