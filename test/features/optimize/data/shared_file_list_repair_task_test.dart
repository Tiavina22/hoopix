import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/optimize/data/datasources/shared_file_list_repair_task.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _valid() => ProcessResult.success('OK');
ProcessResult _corrupt() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('plutil', 1, 'bad'));

void main() {
  late Directory home;
  late String sflDir;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_sfl_');
    sflDir =
        '${home.path}/Library/Application Support/com.apple.sharedfilelist';
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<File> createSfl(String relative) async {
    final file = File('$sflDir/$relative');
    await file.create(recursive: true);
    return file;
  }

  test('action id matches the catalog', () async {
    final result = await SharedFileListRepairTask(
      home: home.path,
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.task.action, 'shared_file_list_repair');
  });

  test('unchanged when the directory does not exist', () async {
    final result = await SharedFileListRepairTask(
      home: home.path,
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
  });

  test('unchanged when every list passes plutil -lint', () async {
    final file = await createSfl('com.apple.LSSharedFileList.sfl2');

    final result = await SharedFileListRepairTask(
      home: home.path,
      probe: FakeProcessRunner({'plutil -lint ${file.path}': _valid()}),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
    expect(file.existsSync(), isTrue);
  });

  test('removes a corrupted list and reports applied', () async {
    final file = await createSfl('com.apple.LSSharedFileList.sfl3');

    final result = await SharedFileListRepairTask(
      home: home.path,
      probe: FakeProcessRunner({'plutil -lint ${file.path}': _corrupt()}),
    ).run();

    expect(result.outcome, OptimizeOutcome.applied);
    expect(file.existsSync(), isFalse);
  });

  test(
    'never touches an ApplicationRecentDocuments list, even corrupted',
    () async {
      final file = await createSfl(
        'com.apple.LSSharedFileList.ApplicationRecentDocuments/foo.sfl2',
      );

      final result = await SharedFileListRepairTask(
        home: home.path,
        probe: FakeProcessRunner({'plutil -lint ${file.path}': _corrupt()}),
      ).run();

      expect(result.outcome, OptimizeOutcome.unchanged);
      expect(file.existsSync(), isTrue);
    },
  );

  test('ignores files that are not .sfl2/.sfl3', () async {
    final file = await createSfl('notes.txt');

    final result = await SharedFileListRepairTask(
      home: home.path,
      probe: FakeProcessRunner(const {}),
    ).run();

    expect(result.outcome, OptimizeOutcome.unchanged);
    expect(file.existsSync(), isTrue);
  });
}
