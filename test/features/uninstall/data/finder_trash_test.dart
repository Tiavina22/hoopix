import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/finder_trash.dart';

class _Osascript extends ProcessRunner {
  _Osascript({this.timeOut = false});

  final bool timeOut;
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    return timeOut
        ? ProcessResult.failure(
            ProcessFailure.timedOut(executable, const Duration(minutes: 2)),
          )
        : ProcessResult.success('');
  }
}

void main() {
  const capcut = '/Applications/CapCut.app';

  group('isTopLevelApplication', () {
    test('accepts exactly one .app directly in /Applications', () {
      expect(isTopLevelApplication(capcut), isTrue);
      expect(isTopLevelApplication('$capcut/'), isTrue);
    });

    test('refuses anything deeper, elsewhere, or escaping', () {
      for (final path in [
        '/Applications/Utilities/Tool.app',
        '/Applications/CapCut.app/Contents',
        '/Users/me/Applications/CapCut.app',
        '/Applications/.app',
        '/Applications/../System/Finder.app',
        '/Applications/CapCut',
        '/Applications',
      ]) {
        expect(isTopLevelApplication(path), isFalse, reason: path);
      }
    });
  });

  test(
    'asks Finder with the path as an argument, then checks it is gone',
    () async {
      final osascript = _Osascript();
      var exists = true;
      final finder = FinderTrash(
        runner: osascript,
        typeOf: (_) => exists
            ? FileSystemEntityType.directory
            : FileSystemEntityType.notFound,
      );
      // Finder's move happens during the call.
      exists = false;

      expect(await finder.moveApplication(capcut), isTrue);
      final call = osascript.calls.single;
      expect(call.first, 'osascript');
      expect(call.last, capcut);
      final script = [for (var i = 2; i < call.length - 1; i += 2) call[i]];
      expect(script.join('\n'), isNot(contains('CapCut')));
      expect(script, contains('tell application "Finder"'));
    },
  );

  test(
    'a bundle still on disk is not a success, whatever osascript says',
    () async {
      final finder = FinderTrash(
        runner: _Osascript(),
        typeOf: (_) => FileSystemEntityType.directory,
      );

      expect(await finder.moveApplication(capcut), isFalse);
    },
  );

  test('a password prompt left unanswered is not a success', () async {
    final finder = FinderTrash(
      runner: _Osascript(timeOut: true),
      typeOf: (_) => FileSystemEntityType.notFound,
    );

    expect(await finder.moveApplication(capcut), isFalse);
  });

  test('never hands Finder anything but a top-level app', () async {
    final osascript = _Osascript();
    final finder = FinderTrash(
      runner: osascript,
      typeOf: (_) => FileSystemEntityType.notFound,
    );

    expect(
      await finder.moveApplication(
        '/Users/mac/Library/Containers/com.lemon.lvoverseas',
      ),
      isFalse,
    );
    expect(osascript.calls, isEmpty);
  });
}
