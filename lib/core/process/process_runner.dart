import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'process_failure.dart';

/// Result of running an external process: either captured stdout, or a
/// typed [ProcessFailure] describing why no output was produced.
///
/// A failure can still carry [stdout]: `du` exits non-zero as soon as a
/// single descendant anywhere in the tree is unreadable (every TCC-protected
/// folder under `~/Library`, in practice) while still printing a perfectly
/// usable total. Discarding that output would turn the most interesting
/// directories into hard errors.
class ProcessResult {
  const ProcessResult._({this.stdout, this.failure});

  factory ProcessResult.success(String stdout) =>
      ProcessResult._(stdout: stdout);

  factory ProcessResult.failure(ProcessFailure failure, {String? stdout}) =>
      ProcessResult._(failure: failure, stdout: stdout);

  final String? stdout;
  final ProcessFailure? failure;

  bool get isSuccess => failure == null;
}

/// The tools macOS itself ships that hoopix runs, by absolute path.
///
/// Many of them answer safety questions — whether a file is open (`lsof`),
/// whether an app is running (`ps`, `pgrep`), a path's identity (`stat`),
/// a bundle's id (`plutil`) — and a bare name is looked up through `PATH`.
/// Launched from a terminal (`flutter run`, `open` from a shell), hoopix
/// inherits that shell's `PATH`, which usually puts user-writable folders
/// such as `~/.local/bin` first, where a stand-in `lsof` could answer
/// "nothing open". By path, the answer always comes from the system's own
/// tool. Tools the user installs (npm, bun, brew, go, ...) are not here:
/// they live wherever the user put them.
const systemToolPaths = {
  'defaults': '/usr/bin/defaults',
  'df': '/bin/df',
  'dscacheutil': '/usr/bin/dscacheutil',
  'du': '/usr/bin/du',
  'env': '/usr/bin/env',
  'file': '/usr/bin/file',
  'getconf': '/usr/bin/getconf',
  'hostname': '/bin/hostname',
  'id': '/usr/bin/id',
  'killall': '/usr/bin/killall',
  'launchctl': '/bin/launchctl',
  'lsof': '/usr/sbin/lsof',
  'mdfind': '/usr/bin/mdfind',
  'mdutil': '/usr/bin/mdutil',
  'netstat': '/usr/sbin/netstat',
  'open': '/usr/bin/open',
  'osascript': '/usr/bin/osascript',
  'pgrep': '/usr/bin/pgrep',
  'pkgutil': '/usr/sbin/pkgutil',
  'pkill': '/usr/bin/pkill',
  'plutil': '/usr/bin/plutil',
  'pmset': '/usr/bin/pmset',
  'ps': '/bin/ps',
  'qlmanage': '/usr/bin/qlmanage',
  'route': '/sbin/route',
  'scutil': '/usr/sbin/scutil',
  'sqlite3': '/usr/bin/sqlite3',
  'stat': '/usr/bin/stat',
  'sw_vers': '/usr/bin/sw_vers',
  'sysctl': '/usr/sbin/sysctl',
  'system_profiler': '/usr/sbin/system_profiler',
  'test': '/bin/test',
  'tmutil': '/usr/bin/tmutil',
  'unzip': '/usr/bin/unzip',
  'vm_stat': '/usr/bin/vm_stat',
  'xcode-select': '/usr/bin/xcode-select',
  'zipinfo': '/usr/bin/zipinfo',
};

/// [executable] by absolute path when it is one of [systemToolPaths],
/// unchanged otherwise.
String resolveExecutable(String executable) =>
    systemToolPaths[executable] ?? executable;

/// Timeout-bounded wrapper over [Process.start]. Every feature datasource
/// that shells out to a macOS CLI tool goes through this instead of calling
/// `dart:io` directly, so every external call shares the same bounded-probe,
/// degrade-instead-of-hang behavior rather than risking a frozen UI.
class ProcessRunner {
  const ProcessRunner({this.timeout = const Duration(seconds: 2)});

  final Duration timeout;

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final Process process;
    try {
      process = await Process.start(resolveExecutable(executable), arguments);
    } on Object catch (error) {
      return ProcessResult.failure(
        ProcessFailure.notFound(executable, error.toString()),
      );
    }

    // Malformed bytes become U+FFFD instead of throwing: a file name that
    // is not valid UTF-8 is ordinary `find`/`du` output on a real Mac, and a
    // throwing decoder turned it into an unhandled exception that killed the
    // whole scan. A mangled name can only ever point at a path that does not
    // exist, so nothing downstream can act on a different file because of it.
    final stdoutFuture = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();

    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      return ProcessResult.failure(
        ProcessFailure.timedOut(executable, timeout),
      );
    }

    final stdout = await stdoutFuture;
    if (exitCode != 0) {
      final stderr = await stderrFuture;
      return ProcessResult.failure(
        ProcessFailure.nonZeroExit(executable, exitCode, stderr),
        stdout: stdout,
      );
    }

    return ProcessResult.success(stdout);
  }
}
