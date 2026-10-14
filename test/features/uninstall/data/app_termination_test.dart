import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/app_termination.dart';

const _app = '/Applications/Notes Pro.app';
const _plist = '$_app/Contents/Info.plist';

ProcessResult _ok([String out = '']) => ProcessResult.success(out);
ProcessResult _noMatch() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('pgrep', 1, ''));

/// Plays a process that exits after a given step: `pgrep` answers
/// "running" until [exitsAfter] has been run, then "no match".
class _ScriptedProcess extends ProcessRunner {
  _ScriptedProcess({
    this.executable = 'NotesPro',
    this.bundleId = 'com.example.notespro',
    this.exitsAfter,
    this.running = true,
  });

  final String? executable;
  final String? bundleId;

  /// The command (joined) after which the process is gone, or null for one
  /// that never exits.
  final String? exitsAfter;
  bool running;
  final calls = <String>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final call = [executable, ...arguments].join(' ');
    calls.add(call);
    if (executable == '/usr/bin/plutil') {
      final key = arguments[1];
      final value = key == 'CFBundleExecutable' ? this.executable : bundleId;
      return value == null
          ? ProcessResult.failure(ProcessFailure.nonZeroExit('plutil', 1, ''))
          : _ok('$value\n');
    }
    if (executable == '/usr/bin/pgrep') return running ? _ok('42') : _noMatch();
    if (exitsAfter != null && call.startsWith(exitsAfter!)) running = false;
    return _ok();
  }
}

AppTermination _termination(_ScriptedProcess process) =>
    AppTermination(runner: process, scriptRunner: process, sleep: (_) async {});

void main() {
  test('an app that is not running is left alone', () async {
    final process = _ScriptedProcess(running: false);

    expect(
      await _termination(process).quit(_app, displayName: 'Notes Pro'),
      isTrue,
    );
    expect(process.calls.where((c) => c.contains('osascript')), isEmpty);
    expect(process.calls.where((c) => c.contains('pkill')), isEmpty);
  });

  test('asks the app to quit by bundle id, through argv, and stops there '
      'once it does', () async {
    final process = _ScriptedProcess(exitsAfter: '/usr/bin/osascript');

    expect(
      await _termination(process).quit(_app, displayName: 'Notes Pro'),
      isTrue,
    );
    final quit = process.calls.singleWhere((c) => c.contains('osascript'));
    expect(quit, contains('tell application id (item 1 of argv) to quit'));
    expect(quit, endsWith(' com.example.notespro'));
    expect(process.calls.where((c) => c.contains('pkill')), isEmpty);
  });

  test('sends SIGTERM to an app that ignores Quit, and no more once it '
      'exits', () async {
    final process = _ScriptedProcess(exitsAfter: '/usr/bin/pkill -x NotesPro');

    expect(
      await _termination(process).quit(_app, displayName: 'Notes Pro'),
      isTrue,
    );
    expect(process.calls, contains('/usr/bin/pkill -x NotesPro'));
    expect(process.calls, isNot(contains('/usr/bin/pkill -9 -x NotesPro')));
  });

  test(
    'ends with SIGKILL, and reports a process that survives even that',
    () async {
      final process = _ScriptedProcess();

      expect(
        await _termination(process).quit(_app, displayName: 'Notes Pro'),
        isFalse,
      );
      expect(process.calls, contains('/usr/bin/pkill -9 -x NotesPro'));
    },
  );

  test(
    'never quits or signals a system process name a bundle claims',
    () async {
      final process = _ScriptedProcess(executable: 'Finder');

      expect(
        await _termination(process).quit(_app, displayName: 'Notes Pro'),
        isFalse,
      );
      expect(process.calls.where((c) => c.contains('osascript')), isEmpty);
      expect(process.calls.where((c) => c.contains('pkill')), isEmpty);
    },
  );

  test(
    'without a readable Info.plist, matches and quits by display name',
    () async {
      final process = _ScriptedProcess(
        executable: null,
        bundleId: null,
        exitsAfter: '/usr/bin/osascript',
      );

      expect(
        await _termination(process).quit(_app, displayName: 'Notes Pro'),
        isTrue,
      );
      expect(process.calls, contains('/usr/bin/pgrep -x Notes Pro'));
      final quit = process.calls.singleWhere((c) => c.contains('osascript'));
      expect(quit, contains('tell application (item 1 of argv) to quit'));
      expect(quit, endsWith(' Notes Pro'));
    },
  );

  test('runningProcess names the process only while it runs', () async {
    expect(
      await _termination(
        _ScriptedProcess(),
      ).runningProcess(_app, displayName: 'Notes Pro'),
      'NotesPro',
    );
    expect(
      await _termination(
        _ScriptedProcess(running: false),
      ).runningProcess(_app, displayName: 'Notes Pro'),
      isNull,
    );
  });

  test('reads identity from the bundle Info.plist', () async {
    final process = _ScriptedProcess(running: false);

    await _termination(process).quit(_app, displayName: 'Notes Pro');

    expect(
      process.calls,
      contains('/usr/bin/plutil -extract CFBundleExecutable raw $_plist'),
    );
  });
}
