import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/live_cache_guard.dart';

import '../../../support/fake_process_runner.dart';

const _table = 'ps -axo pid,ppid,comm,args';

/// A process table with one unrelated process in it.
ProcessResult _quietTable() => ProcessResult.success(
  '  PID  PPID COMM             ARGS\n'
  '  501     1 /usr/libexec/sync /usr/libexec/syncdefaultsd\n',
);

ProcessResult _silentNoMatch() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('lsof', 1, ''));

class _Recording extends FakeProcessRunner {
  _Recording(super.responses);

  final calls = <String>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) {
    calls.add([executable, ...arguments].join(' '));
    return super.run(executable, arguments);
  }
}

void main() {
  late Directory home;
  late String caches;
  late String containerCaches;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_live_cache_');
    caches = '${home.path}/Library/Caches';
    containerCaches =
        '${home.path}/Library/Containers/com.example.App/Data/Library/Caches';
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<String> makeFile(String path) async {
    await File(path).create(recursive: true);
    return path;
  }

  LiveCacheGuard guardWith({
    required Map<String, ProcessResult> processList,
    FakeProcessRunner? openFiles,
    FakeProcessRunner? metadata,
  }) => LiveCacheGuard(
    home: home.path,
    processList: FakeProcessRunner(processList),
    openFiles: openFiles ?? FakeProcessRunner(const {}),
    metadata: metadata ?? FakeProcessRunner(const {}),
    selfPid: 99999,
  );

  test('leaves a path outside every reverse-DNS cache tree alone, without '
      'reading the process list', () async {
    final processList = _Recording(const {});
    final guard = LiveCacheGuard(
      home: home.path,
      processList: processList,
      selfPid: 99999,
    );

    final refusals = await guard.refusals([
      '$caches/Homebrew',
      '${home.path}/.npm',
    ]);

    expect(refusals, isEmpty);
    expect(processList.calls, isEmpty);
  });

  test(
    'refuses every scoped path when the process list is unreadable',
    () async {
      final path = '$caches/com.example.App';
      final guard = guardWith(
        processList: {
          _table: ProcessResult.failure(
            ProcessFailure.nonZeroExit('ps', 1, ''),
          ),
        },
      );

      final refusals = await guard.refusals([path]);

      expect(refusals[path], 'skipped: could not read the process list');
    },
  );

  test(
    'refuses a cache whose owner is running, without probing files',
    () async {
      final path = await makeFile('$caches/com.example.App/Cache.db');
      final openFiles = _Recording(const {});
      final guard = guardWith(
        processList: {
          _table: ProcessResult.success(
            '  PID  PPID COMM             ARGS\n'
            '  601     1 /Applications/Exa /Applications/Example.app/Contents/'
            'MacOS/Example com.example.App\n',
          ),
        },
        openFiles: openFiles,
      );

      final refusals = await guard.refusals([path]);

      expect(refusals[path], 'skipped: com.example.App is running');
      expect(openFiles.calls, isEmpty);
    },
  );

  group('a ~/Library/Caches/<id> directory', () {
    test('checks each SQLite family inside it over the members that '
        'exist, and lets it go when none is open', () async {
      final dir = '$caches/com.example.App';
      await makeFile('$dir/Cache.db');
      await makeFile('$dir/Cache.db-wal');
      await makeFile('$dir/fsCachedData');
      final openFiles = _Recording({
        'lsof -F n -- $dir/Cache.db $dir/Cache.db-wal': _silentNoMatch(),
      });
      final guard = guardWith(
        processList: {_table: _quietTable()},
        openFiles: openFiles,
      );

      final refusals = await guard.refusals([dir]);

      expect(refusals, isEmpty);
      expect(openFiles.calls, ['lsof -F n -- $dir/Cache.db $dir/Cache.db-wal']);
    });

    test('refuses it when a database in it is open', () async {
      final dir = '$caches/com.example.App';
      await makeFile('$dir/Cache.db');
      final guard = guardWith(
        processList: {_table: _quietTable()},
        openFiles: FakeProcessRunner({
          'lsof -F n -- $dir/Cache.db': ProcessResult.success(
            'p700\nn$dir/Cache.db\n',
          ),
        }),
      );

      final refusals = await guard.refusals([dir]);

      expect(refusals[dir], 'skipped: a file in it is open');
    });

    test('a record on a partial no-match still means open', () async {
      // lsof exits 1 when only some of the requested names are open.
      final dir = '$caches/com.example.App';
      await makeFile('$dir/Cache.db');
      await makeFile('$dir/Cache.db-shm');
      final guard = guardWith(
        processList: {_table: _quietTable()},
        openFiles: FakeProcessRunner({
          'lsof -F n -- $dir/Cache.db $dir/Cache.db-shm': ProcessResult.failure(
            ProcessFailure.nonZeroExit('lsof', 1, ''),
            stdout: 'p700\nn$dir/Cache.db-shm\n',
          ),
        }),
      );

      final refusals = await guard.refusals([dir]);

      expect(refusals[dir], 'skipped: a file in it is open');
    });

    test('refuses it when lsof cannot give a clean answer', () async {
      final dir = '$caches/com.example.App';
      await makeFile('$dir/Cache.db');
      for (final inconclusive in [
        ProcessResult.failure(
          ProcessFailure.nonZeroExit('lsof', 1, 'lsof: WARNING: can\'t stat()'),
        ),
        ProcessResult.failure(ProcessFailure.nonZeroExit('lsof', 2, '')),
        ProcessResult.failure(
          ProcessFailure.timedOut('lsof', const Duration(seconds: 5)),
        ),
        ProcessResult.failure(ProcessFailure.notFound('lsof', 'missing')),
      ]) {
        final guard = guardWith(
          processList: {_table: _quietTable()},
          openFiles: FakeProcessRunner({
            'lsof -F n -- $dir/Cache.db': inconclusive,
          }),
        );

        final refusals = await guard.refusals([dir]);

        expect(
          refusals[dir],
          'skipped: could not confirm no file in it is open',
          reason: '${inconclusive.failure}',
        );
      }
    });

    test('with no database in it, only the owner decides', () async {
      final dir = '$caches/com.example.App';
      await makeFile('$dir/fsCachedData/blob');
      final openFiles = _Recording(const {});
      final guard = guardWith(
        processList: {_table: _quietTable()},
        openFiles: openFiles,
      );

      expect(await guard.refusals([dir]), isEmpty);
      expect(openFiles.calls, isEmpty);
    });

    test('an unreadable directory is not "no SQLite here"', () async {
      final dir = '$caches/com.example.App';
      await Directory(dir).create(recursive: true);
      final guard = LiveCacheGuard(
        home: home.path,
        processList: FakeProcessRunner({_table: _quietTable()}),
        selfPid: 99999,
        filesIn: (_) => null,
      );

      final refusals = await guard.refusals([dir]);

      expect(refusals[dir], 'skipped: could not confirm no file in it is open');
    });
  });

  group('a container cache', () {
    Map<String, ProcessResult> identity(String path, String value) => {
      'stat -f %d:%i ${path.substring(0, path.lastIndexOf('/'))} $path':
          ProcessResult.success(value),
    };

    test(
      'checks every descendant and lets a quiet, unchanged one go',
      () async {
        final dir = '$containerCaches/WebKit';
        await makeFile('$dir/blob');
        final openFiles = _Recording({'lsof -F pfn +D $dir': _silentNoMatch()});
        final guard = guardWith(
          processList: {_table: _quietTable()},
          openFiles: openFiles,
          metadata: FakeProcessRunner(identity(dir, '1:2\n1:3\n')),
        );

        expect(await guard.refusals([dir]), isEmpty);
        expect(openFiles.calls, ['lsof -F pfn +D $dir']);
      },
    );

    test('refuses it when any descendant is open', () async {
      final dir = '$containerCaches/WebKit';
      await makeFile('$dir/blob');
      final guard = guardWith(
        processList: {_table: _quietTable()},
        openFiles: FakeProcessRunner({
          'lsof -F pfn +D $dir': ProcessResult.success(
            'p812\nf12\nn$dir/blob\n',
          ),
        }),
        metadata: FakeProcessRunner(identity(dir, '1:2\n1:3\n')),
      );

      expect(
        (await guard.refusals([dir]))[dir],
        'skipped: a file in it is open',
      );
    });

    test('probes a single file by name, not with +D', () async {
      final file = await makeFile('$containerCaches/Cache.db');
      final openFiles = _Recording({'lsof -F pfn -- $file': _silentNoMatch()});
      final guard = guardWith(
        processList: {_table: _quietTable()},
        openFiles: openFiles,
        metadata: FakeProcessRunner(identity(file, '1:2\n1:3\n')),
      );

      expect(await guard.refusals([file]), isEmpty);
      expect(openFiles.calls, ['lsof -F pfn -- $file']);
    });

    test('refuses a path replaced while lsof ran', () async {
      final dir = '$containerCaches/WebKit';
      await makeFile('$dir/blob');
      var reads = 0;
      final guard = LiveCacheGuard(
        home: home.path,
        processList: FakeProcessRunner({_table: _quietTable()}),
        openFiles: FakeProcessRunner({'lsof -F pfn +D $dir': _silentNoMatch()}),
        metadata: _Sequenced(() => reads++ == 0 ? '1:2\n1:3\n' : '1:2\n1:9\n'),
        selfPid: 99999,
      );

      expect(
        (await guard.refusals([dir]))[dir],
        'skipped: could not confirm no file in it is open',
      );
    });

    test('a path that no longer exists has nothing open', () async {
      final guard = guardWith(processList: {_table: _quietTable()});

      expect(await guard.refusals(['$containerCaches/gone']), isEmpty);
    });
  });
}

/// Answers every call with the next value [next] produces.
class _Sequenced extends ProcessRunner {
  _Sequenced(this.next);

  final String Function() next;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async =>
      ProcessResult.success(next());
}
