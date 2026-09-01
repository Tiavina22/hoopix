import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/app_leftovers_local_datasource.dart';

/// [claudeRunning] gates `pgrep -x Claude`; [installedBundleIds] gates
/// `mdfind` — a bundle id in the set is "found", matching a real machine
/// where Spotlight actually has that app indexed.
class _FakeProbe extends ProcessRunner {
  _FakeProbe({this.claudeRunning = false, this.installedBundleIds = const {}});

  final bool claudeRunning;
  final Set<String> installedBundleIds;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    if (executable == 'pgrep') {
      return claudeRunning
          ? ProcessResult.success('123')
          : ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
    }
    if (executable == 'mdfind') {
      final query = arguments.single;
      final found = installedBundleIds.any(query.contains);
      return ProcessResult.success(found ? '/Applications/Example.app' : '');
    }
    return ProcessResult.failure(
      ProcessFailure.notFound(executable, 'unexpected call'),
    );
  }
}

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_app_leftovers_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  Future<void> touch(String relative, {DateTime? modified}) async {
    final file = File('${home.path}/$relative');
    await file.create(recursive: true);
    if (modified != null) file.setLastModifiedSync(modified);
  }

  // File.setLastModifiedSync refuses a directory path (EISDIR), so backdating
  // a bundle directory's own mtime goes through BSD touch instead.
  void backdateDirectory(String path, DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${time.year}${two(time.month)}${two(time.day)}'
        '${two(time.hour)}${two(time.minute)}.${two(time.second)}';
    final result = Process.runSync('touch', ['-t', stamp, path]);
    if (result.exitCode != 0) {
      throw StateError('touch failed: ${result.stderr}');
    }
  }

  Future<List<String>> targets({
    bool claudeRunning = false,
    Set<String> installedBundleIds = const {},
  }) async {
    final source = AppLeftoversLocalDataSource(
      home: home.path,
      probe: _FakeProbe(
        claudeRunning: claudeRunning,
        installedBundleIds: installedBundleIds,
      ),
    );
    return (await source.enumerate()).paths;
  }

  test('section name matches the constant every other section uses', () async {
    final source = AppLeftoversLocalDataSource(
      home: home.path,
      probe: _FakeProbe(),
    );
    final result = await source.enumerate();
    expect(result.section, AppLeftoversLocalDataSource.appLeftovers);
  });

  group('Claude VM bundles', () {
    Future<void> makeOldBundle() async {
      const relative = 'Library/Application Support/Claude/vms/qemu.bundle';
      await makeDir(relative);
      backdateDirectory(
        '${home.path}/$relative',
        DateTime.now().subtract(const Duration(days: 10)),
      );
    }

    test('proposes an old bundle when Claude is gone', () async {
      await makeOldBundle();

      final result = await targets();

      expect(
        result,
        contains(
          '${home.path}/Library/Application Support/Claude/vms/qemu.bundle',
        ),
      );
    });

    test('leaves the bundle alone while Claude is running', () async {
      await makeOldBundle();

      final result = await targets(claudeRunning: true);

      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Application Support/Claude/vms/qemu.bundle',
          ),
        ),
      );
    });

    test(
      'leaves the bundle alone when Claude Desktop is still installed',
      () async {
        await makeOldBundle();

        final result = await targets(
          installedBundleIds: {'com.anthropic.claudefordesktop'},
        );

        expect(
          result,
          isNot(
            contains(
              '${home.path}/Library/Application Support/Claude/vms/qemu.bundle',
            ),
          ),
        );
      },
    );

    test('leaves a bundle touched within the last 7 days alone', () async {
      await touch(
        'Library/Application Support/Claude/vms/qemu.bundle/marker',
        modified: DateTime.now().subtract(const Duration(days: 1)),
      );

      final result = await targets();

      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Application Support/Claude/vms/qemu.bundle',
          ),
        ),
      );
    });
  });

  group('CleanMyMac X container stubs', () {
    test('proposes a stub container when CleanMyMac X is gone', () async {
      await touch(
        'Library/Containers/com.macpaw.CleanMyMac4/.com.apple.containermanagerd.metadata.plist',
      );

      final result = await targets();

      expect(
        result,
        contains('${home.path}/Library/Containers/com.macpaw.CleanMyMac4'),
      );
    });

    test('matches a TeamID-prefixed helper container too', () async {
      await touch(
        'Library/Containers/S8EX82NJP6.com.macpaw.CleanMyMac4.Agent'
        '/.com.apple.containermanagerd.metadata.plist',
      );

      final result = await targets();

      expect(
        result,
        contains(
          '${home.path}/Library/Containers/S8EX82NJP6.com.macpaw.CleanMyMac4.Agent',
        ),
      );
    });

    test(
      'never touches a container holding anything besides the metadata file',
      () async {
        await touch(
          'Library/Containers/com.macpaw.CleanMyMac4/.com.apple.containermanagerd.metadata.plist',
        );
        await makeDir('Library/Containers/com.macpaw.CleanMyMac4/Data');

        final result = await targets();

        expect(
          result,
          isNot(
            contains('${home.path}/Library/Containers/com.macpaw.CleanMyMac4'),
          ),
        );
      },
    );

    test(
      'leaves the container alone when CleanMyMac X.app is installed',
      () async {
        await touch(
          'Library/Containers/com.macpaw.CleanMyMac4/.com.apple.containermanagerd.metadata.plist',
        );
        await makeDir('Applications/CleanMyMac X.app');

        final result = await targets();

        expect(
          result,
          isNot(
            contains('${home.path}/Library/Containers/com.macpaw.CleanMyMac4'),
          ),
        );
      },
    );

    test('leaves an unrelated container alone', () async {
      await touch(
        'Library/Containers/com.example.other/.com.apple.containermanagerd.metadata.plist',
      );

      final result = await targets();

      expect(
        result,
        isNot(contains('${home.path}/Library/Containers/com.example.other')),
      );
    });
  });

  test('a missing home tree proposes nothing and does not throw', () async {
    final result = await targets();
    expect(result, isEmpty);
  });
}
