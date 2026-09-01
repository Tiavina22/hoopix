import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/utm_caches_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _running() => ProcessResult.success('123');
ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _unknown() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 2, 'usage'));

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_utm_caches_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  Future<List<String>> targets(ProcessResult response) async {
    final source = UtmCachesLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner({'pgrep -x UTM': response})),
    );
    return (await source.enumerate()).paths;
  }

  test('section name matches the constant Virtualization uses', () async {
    final source = UtmCachesLocalDataSource(
      home: home.path,
      guard: ProcessGuard(FakeProcessRunner(const {})),
    );
    final result = await source.enumerate();
    expect(result.section, CleanSectionsLocalDataSource.virtualization);
  });

  test('reaches the sandbox temp directory while UTM is closed', () async {
    await makeDir('Library/Containers/com.utmapp.UTM/Data/tmp/download.iso');

    final result = await targets(_notRunning());

    expect(
      result,
      contains(
        '${home.path}/Library/Containers/com.utmapp.UTM/Data/tmp/download.iso',
      ),
    );
  });

  test('proposes nothing while UTM is running', () async {
    await makeDir('Library/Containers/com.utmapp.UTM/Data/tmp/download.iso');

    expect(await targets(_running()), isEmpty);
  });

  test('proposes nothing when the process state cannot be confirmed', () async {
    await makeDir('Library/Containers/com.utmapp.UTM/Data/tmp/download.iso');

    expect(await targets(_unknown()), isEmpty);
  });

  test('a missing home tree does not throw', () async {
    expect(await targets(_notRunning()), isEmpty);
  });
}
