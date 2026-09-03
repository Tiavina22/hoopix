import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/launch_agents_cleanup_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _programArgs(String value) => ProcessResult.success('$value\n');
ProcessResult _missing() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('PlistBuddy', 1, ''));

void main() {
  late Directory home;
  late String agentsDir;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_launch_agents_');
    agentsDir = '${home.path}/Library/LaunchAgents';
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<File> agent(String name) async {
    final file = File('$agentsDir/$name.plist');
    await file.create(recursive: true);
    return file;
  }

  test('action id matches the catalog', () async {
    final result = await LaunchAgentsCleanupTask(
      home: home.path,
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.task.action, 'launch_agents_cleanup');
  });

  test('unchanged when the LaunchAgents directory does not exist', () async {
    final result = await LaunchAgentsCleanupTask(
      home: home.path,
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('unchanged when a bare command name resolves via PATH', () async {
    final file = await agent('com.example.bare');

    final result = await LaunchAgentsCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        '/usr/libexec/PlistBuddy -c Print :ProgramArguments:0 ${file.path}':
            _programArgs('node'),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
    expect(file.existsSync(), isTrue);
  });

  test('unchanged when the absolute binary path exists', () async {
    final file = await agent('com.example.present');
    final binary = File('${home.path}/bin/tool');
    await binary.create(recursive: true);

    final result = await LaunchAgentsCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        '/usr/libexec/PlistBuddy -c Print :ProgramArguments:0 ${file.path}':
            _programArgs(binary.path),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test(
    'unchanged when the missing binary lives on an unmounted /Volumes disk',
    () async {
      final file = await agent('com.example.unmounted');

      final result = await LaunchAgentsCleanupTask(
        home: home.path,
        probe: FakeProcessRunner({
          '/usr/libexec/PlistBuddy -c Print :ProgramArguments:0 ${file.path}':
              _programArgs('/Volumes/ExternalDisk/tool'),
        }),
      ).run();

      expect(result.outcome, OptimizeOutcome.unchanged);
      expect(file.existsSync(), isTrue);
    },
  );

  test('removes an agent whose absolute binary is genuinely missing, falling '
      'back to Program when ProgramArguments:0 is empty', () async {
    final file = await agent('com.example.broken');

    final result = await LaunchAgentsCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        '/usr/libexec/PlistBuddy -c Print :ProgramArguments:0 ${file.path}':
            _missing(),
        '/usr/libexec/PlistBuddy -c Print :Program ${file.path}': _programArgs(
          '${home.path}/gone/tool',
        ),
        'launchctl unload ${file.path}': ProcessResult.success(''),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
    expect(file.existsSync(), isFalse);
  });

  test('removes the plist even when launchctl unload itself fails', () async {
    final file = await agent('com.example.stubborn');

    final result = await LaunchAgentsCleanupTask(
      home: home.path,
      probe: FakeProcessRunner({
        '/usr/libexec/PlistBuddy -c Print :ProgramArguments:0 ${file.path}':
            _programArgs('${home.path}/gone/tool'),
        'launchctl unload ${file.path}': ProcessResult.failure(
          ProcessFailure.nonZeroExit('launchctl', 1, 'not loaded'),
        ),
      }),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
    expect(file.existsSync(), isFalse);
  });
}
