import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/developer_tools_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/pnpm_store_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _ok(String stdout) => ProcessResult.success(stdout);
ProcessResult _fail() =>
    ProcessResult.failure(ProcessFailure.notFound('pnpm', 'not found'));
ProcessResult _notRunning() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));
ProcessResult _running() => ProcessResult.success('123');
ProcessResult _unknown() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 2, 'usage'));

const _busyPattern = r'(^|/)pnpm(\.cjs)?([[:space:]]|$)';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_pnpm_store_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeExecutable(String relative) async {
    final file = File('${home.path}/$relative');
    await file.create(recursive: true);
    await Process.run('chmod', ['+x', file.path]);
  }

  Future<CleanSectionTargets> enumerate(
    Map<String, ProcessResult> responses, {
    Map<String, ProcessResult> pgrepResponses = const {},
  }) async {
    final source = PnpmStoreLocalDataSource(
      home: home.path,
      guard: ProcessGuard(
        FakeProcessRunner({
          'pgrep -f $_busyPattern': _notRunning(),
          ...pgrepResponses,
        }),
      ),
      probe: FakeProcessRunner(responses),
    );
    return source.enumerate();
  }

  test('section name matches the constant Developer tools uses', () async {
    final result = await enumerate(const {});
    expect(result.section, DeveloperToolsLocalDataSource.developerTools);
  });

  test('resolves the PATH pnpm store path and proposes it with its prune '
      'command', () async {
    final result = await enumerate({
      'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm --version': _ok('9.1.0'),
      'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm store path': _ok(
        '/Users/me/Library/pnpm/store/v3\n',
      ),
    });

    const store = '/Users/me/Library/pnpm/store/v3';
    expect(result.paths, [store]);
    expect(result.ownerCommands[store], [
      'env',
      'COREPACK_ENABLE_DOWNLOAD_PROMPT=0',
      'pnpm',
      'store',
      'prune',
    ]);
  });

  test('proposes nothing when pnpm is not installed', () async {
    final result = await enumerate({
      'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm --version': _fail(),
    });

    expect(result.paths, isEmpty);
  });

  test('proposes nothing when the resolved store path is unsafe', () async {
    for (final unsafe in ['relative/path', '/a/../b', '']) {
      final result = await enumerate({
        'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm --version': _ok('9.1.0'),
        'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm store path': _ok(unsafe),
      });

      expect(result.paths, isEmpty, reason: 'for "$unsafe"');
    }
  });

  test('tries every mise-installed version alongside PATH pnpm', () async {
    await makeExecutable('.local/share/mise/installs/pnpm/8.15.0/pnpm');

    final result = await enumerate({
      'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm --version': _fail(),
      'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 '
              '${home.path}/.local/share/mise/installs/pnpm/8.15.0/pnpm --version':
          _ok('8.15.0'),
      'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 '
              '${home.path}/.local/share/mise/installs/pnpm/8.15.0/pnpm store path':
          _ok('/Users/me/Library/pnpm/store/v3'),
    });

    expect(result.paths, ['/Users/me/Library/pnpm/store/v3']);
  });

  test(
    'prunes a shared store path only once across two pnpm binaries',
    () async {
      await makeExecutable('.local/share/mise/installs/pnpm/8.15.0/pnpm');
      final miseBin =
          '${home.path}/.local/share/mise/installs/pnpm/8.15.0/pnpm';

      final result = await enumerate({
        'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm --version': _ok('9.1.0'),
        'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm store path': _ok(
          '/Users/me/Library/pnpm/store/v3',
        ),
        'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 $miseBin --version': _ok(
          '8.15.0',
        ),
        'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 $miseBin store path': _ok(
          '/Users/me/Library/pnpm/store/v3',
        ),
      });

      expect(result.paths, ['/Users/me/Library/pnpm/store/v3']);
    },
  );

  test('proposes nothing while a pnpm process is running', () async {
    final result = await enumerate(
      {
        'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm --version': _ok('9.1.0'),
        'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm store path': _ok(
          '/Users/me/Library/pnpm/store/v3',
        ),
      },
      pgrepResponses: {'pgrep -f $_busyPattern': _running()},
    );

    expect(result.paths, isEmpty);
  });

  test('proposes nothing when the process state cannot be confirmed', () async {
    final result = await enumerate(
      {
        'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm --version': _ok('9.1.0'),
        'env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm store path': _ok(
          '/Users/me/Library/pnpm/store/v3',
        ),
      },
      pgrepResponses: {'pgrep -f $_busyPattern': _unknown()},
    );

    expect(result.paths, isEmpty);
  });
}
