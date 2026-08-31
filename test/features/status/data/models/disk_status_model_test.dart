import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/status/data/models/disk_status_model.dart';

// A real `df -k` row for the APFS startup volume. Note the shape that makes
// this tricky: the volume reports the whole 460 GB container as its size,
// only 11.7 GB as its own "Used", and 9.6 GB available — because sibling
// volumes in the same container hold the rest.
const _startupVolumeRow =
    '/dev/disk3s1s1   482797652  12348004  10107984    55%  458734 101079840    0%   /';

void main() {
  group('DiskStatusModel.tryParseRow', () {
    test('derives used space from total minus available, not df\'s column', () {
      // Regression: using df's "Used" column reported the startup disk as 3%
      // full while it was nearly out of space.
      final disk = DiskStatusModel.tryParseRow(_startupVolumeRow);

      expect(disk, isNotNull);
      expect(disk!.mountPoint, '/');
      expect(disk.totalBytes, 482797652 * 1024);
      expect(disk.availableBytes, 10107984 * 1024);
      expect(disk.usedBytes, (482797652 - 10107984) * 1024);
      expect(disk.usedBytes, isNot(12348004 * 1024));
      expect(disk.usedPercent, greaterThan(95));
    });

    test('skips the two-token `map auto_home` automount row', () {
      const row =
          'map auto_home            0         0         0   100%       0         0     -   /System/Volumes/Data/home';

      expect(DiskStatusModel.tryParseRow(row), isNull);
    });

    test('skips the header row', () {
      const row =
          'Filesystem     1024-blocks      Used Available Capacity iused     ifree %iused  Mounted on';

      expect(DiskStatusModel.tryParseRow(row), isNull);
    });
  });
}
