import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/fix_broken_configs_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _valid() => ProcessResult.success('OK');
ProcessResult _corrupt() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('plutil', 1, 'bad'));

void main() {
  late Directory home;
  late String prefsDir;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_fix_configs_');
    prefsDir = '${home.path}/Library/Preferences';
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<File> plist(String relative) async {
    final file = File('$prefsDir/$relative');
    await file.create(recursive: true);
    return file;
  }

  test('action id matches the catalog', () async {
    final result = await FixBrokenConfigsTask(
      home: home.path,
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.task.action, 'fix_broken_configs');
  });

  test('unchanged when the Preferences directory does not exist', () async {
    final result = await FixBrokenConfigsTask(
      home: home.path,
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('removes a corrupted third-party plist and reports applied', () async {
    final file = await plist('com.example.MyApp.plist');

    final result = await FixBrokenConfigsTask(
      home: home.path,
      probe: FakeProcessRunner({'plutil -lint ${file.path}': _corrupt()}),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
    expect(file.existsSync(), isFalse);
  });

  test('never touches a com.apple.* plist, even a corrupted one', () async {
    final file = await plist('com.apple.finder.plist');

    final result = await FixBrokenConfigsTask(
      home: home.path,
      probe: FakeProcessRunner({'plutil -lint ${file.path}': _corrupt()}),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
    expect(file.existsSync(), isTrue);
  });

  test('never touches .GlobalPreferences, even corrupted', () async {
    final file = await plist('.GlobalPreferences.plist');

    final result = await FixBrokenConfigsTask(
      home: home.path,
      probe: FakeProcessRunner({'plutil -lint ${file.path}': _corrupt()}),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
    expect(file.existsSync(), isTrue);
  });

  test(
    'protects loginwindow.plist at the top level but not under ByHost',
    () async {
      final topLevel = await plist('loginwindow.plist');
      final byHost = await plist('ByHost/loginwindow.plist');

      final result = await FixBrokenConfigsTask(
        home: home.path,
        probe: FakeProcessRunner({
          'plutil -lint ${topLevel.path}': _corrupt(),
          'plutil -lint ${byHost.path}': _corrupt(),
        }),
      ).run();

      expect(topLevel.existsSync(), isTrue);
      expect(byHost.existsSync(), isFalse);
      expect(result.outcome, OptimizeOutcome.applied);
    },
  );

  test('does not descend into subdirectories at the top level', () async {
    final nested = await plist('SomeApp/nested.plist');

    final result = await FixBrokenConfigsTask(
      home: home.path,
      probe: FakeProcessRunner({'plutil -lint ${nested.path}': _corrupt()}),
    ).run();

    // Never linted, so never reported as repaired — the top-level pass is
    // not recursive.
    expect(result.outcome, OptimizeOutcome.unchanged);
    expect(nested.existsSync(), isTrue);
  });

  test('leaves a valid plist alone', () async {
    final file = await plist('com.example.Healthy.plist');

    final result = await FixBrokenConfigsTask(
      home: home.path,
      probe: FakeProcessRunner({'plutil -lint ${file.path}': _valid()}),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
    expect(file.existsSync(), isTrue);
  });
}
