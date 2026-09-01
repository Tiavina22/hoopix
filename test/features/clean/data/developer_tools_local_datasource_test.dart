import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/developer_tools_local_datasource.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

class _FakeProbe extends ProcessRunner {
  _FakeProbe(this.available);

  final Set<String> available;
  final calls = <String>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add(executable);
    return available.contains(executable)
        ? ProcessResult.success('1.0.0')
        : ProcessResult.failure(
            ProcessFailure.notFound(executable, 'not found'),
          );
  }
}

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_dev_tools_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  Future<CleanSectionTargets> section({Set<String> available = const {}}) =>
      DeveloperToolsLocalDataSource(
        home: home.path,
        probe: _FakeProbe(available),
      ).enumerate();

  test('section name matches the constant every other section uses', () async {
    final result = await section();
    expect(result.section, DeveloperToolsLocalDataSource.developerTools);
  });

  group('npm', () {
    test(
      'proposes the whole cache as an owner command when npm is on PATH',
      () async {
        await makeDir('.npm');

        final result = await section(available: {'npm'});

        expect(result.paths, contains('${home.path}/.npm'));
        expect(result.ownerCommands['${home.path}/.npm'], [
          'npm',
          'cache',
          'clean',
          '--force',
        ]);
      },
    );

    test(
      'leaves the cache root alone without npm, but still sweeps residuals',
      () async {
        await makeDir('.npm/_cacache/blob');
        await makeDir('.npm/_logs/log-1');

        final result = await section();

        expect(result.paths, isNot(contains('${home.path}/.npm')));
        expect(result.paths, contains('${home.path}/.npm/_cacache/blob'));
        expect(result.paths, contains('${home.path}/.npm/_logs/log-1'));
      },
    );

    test(
      'sweeps residuals even when npm is on PATH, alongside the owner command',
      () async {
        await makeDir('.npm/_npx/entry');

        final result = await section(available: {'npm'});

        expect(result.paths, contains('${home.path}/.npm/_npx/entry'));
      },
    );
  });

  group('corepack', () {
    test(
      'proposes the cache as an owner command when corepack is on PATH',
      () async {
        await makeDir('.cache/node/corepack');

        final result = await section(available: {'corepack'});

        final path = '${home.path}/.cache/node/corepack';
        expect(result.paths, contains(path));
        expect(result.ownerCommands[path], ['corepack', 'cache', 'clean']);
      },
    );

    test('sweeps the cache directly without corepack installed', () async {
      await makeDir('.cache/node/corepack/blob');

      final result = await section();

      final path = '${home.path}/.cache/node/corepack';
      expect(result.paths, isNot(contains(path)));
      expect(result.paths, contains('$path/blob'));
    });
  });

  group('bun', () {
    test(
      'proposes the cache as an owner command when bun is on PATH',
      () async {
        await makeDir('.bun/install/cache');

        final result = await section(available: {'bun'});

        final path = '${home.path}/.bun/install/cache';
        expect(result.paths, contains(path));
        expect(result.ownerCommands[path], ['bun', 'pm', 'cache', 'rm']);
      },
    );

    test('sweeps the cache directly without bun installed', () async {
      await makeDir('.bun/install/cache/blob');

      final result = await section();

      final path = '${home.path}/.bun/install/cache';
      expect(result.paths, isNot(contains(path)));
      expect(result.paths, contains('$path/blob'));
    });

    test('a missing bun cache proposes nothing for bun', () async {
      final result = await section(available: {'bun'});

      expect(result.paths.any((p) => p.contains('.bun')), isFalse);
    });
  });

  test(
    'sweeps tnpm and yarn caches as plain paths, never as owner commands',
    () async {
      await makeDir('.tnpm/_cacache/blob');
      await makeDir('.tnpm/_logs/log-1');
      await makeDir('.yarn/cache/blob');
      await makeDir('Library/Caches/Yarn/blob');

      final result = await section();

      expect(result.paths, contains('${home.path}/.tnpm/_cacache/blob'));
      expect(result.paths, contains('${home.path}/.tnpm/_logs/log-1'));
      expect(result.paths, contains('${home.path}/.yarn/cache/blob'));
      expect(result.paths, contains('${home.path}/Library/Caches/Yarn/blob'));
      expect(result.ownerCommands, isEmpty);
    },
  );

  test('a missing home tree proposes nothing and does not throw', () async {
    final result = await section();
    expect(result.paths, isEmpty);
    expect(result.ownerCommands, isEmpty);
  });
}
