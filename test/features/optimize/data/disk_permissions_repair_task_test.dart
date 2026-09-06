import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/disk_permissions_repair_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_privileged_command.dart';
import '../../../support/fake_process_runner.dart';

ProcessResult _writable() => ProcessResult.success('');
ProcessResult _notWritable() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('test', 1, ''));

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_disk_perms_');
    await Directory('${home.path}/Library/Preferences').create(recursive: true);
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Map<String, ProcessResult> healthyOwnership() => {
    'stat -f %Su ${home.path}': ProcessResult.success(
      '${Platform.environment['USER']}\n',
    ),
    'test -w ${home.path}': _writable(),
    'test -w ${home.path}/Library': _writable(),
    'test -w ${home.path}/Library/Preferences': _writable(),
  };

  test('action id matches the catalog', () async {
    final result = await DiskPermissionsRepairTask(
      home: home.path,
      probe: FakeProcessRunner(healthyOwnership()),
    ).run();

    expect(result.task.action, 'disk_permissions_repair');
  });

  test('unchanged when ownership and writability are all healthy', () async {
    final result = await DiskPermissionsRepairTask(
      home: home.path,
      probe: FakeProcessRunner(healthyOwnership()),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('repairs when the home directory is not writable', () async {
    final probeResponses = healthyOwnership();
    probeResponses['test -w ${home.path}/Library/Preferences'] = _notWritable();
    probeResponses['id -u'] = ProcessResult.success('501\n');

    final privileged = FakePrivilegedCommand({'reset_user_permissions': null});

    final result = await DiskPermissionsRepairTask(
      home: home.path,
      privilegedCommand: privileged,
      probe: FakeProcessRunner(probeResponses),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
    expect(privileged.argumentsByCall.single, {'uid': '501'});
  });

  test('repairs when the home directory has a different owner', () async {
    final probeResponses = healthyOwnership();
    probeResponses['stat -f %Su ${home.path}'] = ProcessResult.success(
      'someone-else\n',
    );
    probeResponses['id -u'] = ProcessResult.success('501\n');

    final result = await DiskPermissionsRepairTask(
      home: home.path,
      privilegedCommand: FakePrivilegedCommand({
        'reset_user_permissions': null,
      }),
      probe: FakeProcessRunner(probeResponses),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
  });

  test('reports failed when elevation is declined', () async {
    final probeResponses = healthyOwnership();
    probeResponses['test -w ${home.path}'] = _notWritable();
    probeResponses['id -u'] = ProcessResult.success('501\n');

    final result = await DiskPermissionsRepairTask(
      home: home.path,
      privilegedCommand: FakePrivilegedCommand({
        'reset_user_permissions': 'declined',
      }),
      probe: FakeProcessRunner(probeResponses),
    ).run();

    expect(result.outcome, OptimizeOutcome.failed);
  });
}
