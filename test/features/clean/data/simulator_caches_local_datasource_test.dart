import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/core/process/simctl_probe.dart';
import 'package:hoopix/features/clean/data/datasources/developer_tools_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/simulator_caches_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _running() => ProcessResult.success('123');
ProcessResult _unknown() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 2, 'usage'));

const _processNames = [
  'Xcode',
  'Simulator',
  'xcodebuild',
  'xctest',
  'XCTRunner',
  'simctl',
];

const _developerDir = '/Applications/Xcode.app/Contents/Developer';
const _bootedJson = '{"devices":{"iOS 18.0":[{"udid":"ABC"}]}}';
const _emptyJson = '{"devices":{"iOS 18.0":[]}}';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_simulator_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Map<String, ProcessResult> allClosed() => {
    for (final name in _processNames) 'pgrep -x $name': _notRunning(),
  };

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  SimulatorCachesLocalDataSource source({
    Map<String, ProcessResult>? processes,
    ProcessResult? booted,
  }) => SimulatorCachesLocalDataSource(
    home: home.path,
    guard: ProcessGuard(FakeProcessRunner(processes ?? allClosed())),
    simctl: SimctlProbe(
      probe: FakeProcessRunner({
        'xcode-select -p': ProcessResult.success(_developerDir),
        'env DEVELOPER_DIR=$_developerDir xcrun --find simctl':
            ProcessResult.success('/path/simctl'),
        'env DEVELOPER_DIR=$_developerDir xcrun simctl list devices booted -j':
            booted ?? ProcessResult.success(_emptyJson),
      }),
      readEnvironment: false,
      // The developer directory has to exist for the usability check.
      directory: Directory.new,
    ),
  );

  Future<CleanSectionTargets> enumerate({
    Map<String, ProcessResult>? processes,
    ProcessResult? booted,
  }) => source(processes: processes, booted: booted).enumerate();

  test('section name matches the constant Developer tools uses', () async {
    expect(
      (await enumerate()).section,
      DeveloperToolsLocalDataSource.developerTools,
    );
  });

  test(
    'reaches all three CoreSimulator roots while nothing is active',
    () async {
      await makeDir('Library/Developer/CoreSimulator/Caches/dyld');
      await makeDir(
        'Library/Developer/CoreSimulator/Devices/ABC-123/data/tmp/x',
      );
      await makeDir('Library/Logs/CoreSimulator/log');

      final result = await enumerate();

      expect(
        result.paths,
        containsAll([
          '${home.path}/Library/Developer/CoreSimulator/Caches/dyld',
          '${home.path}/Library/Developer/CoreSimulator/Devices/ABC-123'
              '/data/tmp/x',
          '${home.path}/Library/Logs/CoreSimulator/log',
        ]),
      );
    },
  );

  test('proposes nothing while a simulator device is booted', () async {
    await makeDir('Library/Developer/CoreSimulator/Caches/dyld');

    final result = await enumerate(booted: ProcessResult.success(_bootedJson));

    expect(result.paths, isEmpty);
  });

  test('proposes nothing when the booted probe cannot be trusted', () async {
    await makeDir('Library/Developer/CoreSimulator/Caches/dyld');

    final result = await enumerate(
      booted: ProcessResult.success('not the expected shape'),
    );

    expect(result.paths, isEmpty);
  });

  test('proposes nothing while any tooling process is running', () async {
    await makeDir('Library/Developer/CoreSimulator/Caches/dyld');

    final processes = allClosed();
    processes['pgrep -x simctl'] = _running();

    expect((await enumerate(processes: processes)).paths, isEmpty);
  });

  test('proposes nothing when a process state cannot be confirmed', () async {
    await makeDir('Library/Developer/CoreSimulator/Caches/dyld');

    final processes = allClosed();
    processes['pgrep -x Simulator'] = _unknown();

    expect((await enumerate(processes: processes)).paths, isEmpty);
  });

  test('every candidate carries both halves of the guard', () async {
    await makeDir('Library/Developer/CoreSimulator/Caches/dyld');

    final result = await enumerate();
    final path = '${home.path}/Library/Developer/CoreSimulator/Caches/dyld';

    expect(result.recheckProcessGuards[path]?.exactNames, _processNames);
    expect(
      result.revalidatorKeys[path],
      SimulatorCachesLocalDataSource.revalidatorKey,
    );
  });

  group('stillEligible', () {
    test('holds while nothing is active', () async {
      expect(await source().stillEligible('/any/path'), isTrue);
    });

    test('refuses once a device is booted', () async {
      final datasource = source(booted: ProcessResult.success(_bootedJson));

      expect(await datasource.stillEligible('/any/path'), isFalse);
    });

    test('refuses once a tooling process is running', () async {
      final processes = allClosed();
      processes['pgrep -x xcodebuild'] = _running();

      expect(
        await source(processes: processes).stillEligible('/any/path'),
        isFalse,
      );
    });
  });

  test('a missing CoreSimulator tree does not throw', () async {
    expect((await enumerate()).paths, isEmpty);
  });
}
