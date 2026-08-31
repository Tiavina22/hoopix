import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/datasources/disk_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

const _dfHeader =
    'Filesystem     1024-blocks      Used Available Capacity iused     ifree %iused  Mounted on';

void main() {
  test('fetch filters pseudo/system mount points from `df -k`', () async {
    final runner = FakeProcessRunner({
      'df -k': ProcessResult.success(
        '$_dfHeader\n'
        '/dev/disk3s1s1   482797652  12348004  10107984    55%  458734 101079840    0%   /\n'
        '/dev/disk3s6     482797652  19936388  10107984    67%      19 101079840    0%   /System/Volumes/VM\n'
        'devfs                  217       217         0   100%     754         0  100%   /dev\n',
      ),
    });

    final disks = await DiskLocalDataSource(runner).fetch();

    expect(disks, hasLength(1));
    expect(disks.single.mountPoint, '/');
  });

  test('fetch hides Xcode simulator runtime volumes', () async {
    // Each installed runtime mounts a read-only volume that is ~98% full by
    // design; listing them buries real disks under permanent red rows.
    final runner = FakeProcessRunner({
      'df -k': ProcessResult.success(
        '$_dfHeader\n'
        '/dev/disk3s1s1   482797652  12348004  10107984    55%  458734 101079840    0%   /\n'
        '/dev/disk5s1      17659904  17159516    455144    98%  627124   4551440   12%   /Library/Developer/CoreSimulator/Volumes/iOS_23F77\n',
      ),
    });

    final disks = await DiskLocalDataSource(runner).fetch();

    expect(disks.map((disk) => disk.mountPoint), ['/']);
  });

  test('fetch keeps external volumes under /Volumes', () async {
    final runner = FakeProcessRunner({
      'df -k': ProcessResult.success(
        '$_dfHeader\n'
        '/dev/disk9s1         51396     36784     13980    73%     191    139800    0%   /Volumes/Backup\n',
      ),
    });

    final disks = await DiskLocalDataSource(runner).fetch();

    expect(disks.single.mountPoint, '/Volumes/Backup');
  });

  test('fetch throws when `df` is unavailable', () async {
    final runner = FakeProcessRunner(const {});
    expect(DiskLocalDataSource(runner).fetch, throwsStateError);
  });
}
