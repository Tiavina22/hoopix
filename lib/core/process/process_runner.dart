import 'dart:async';
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
      process = await Process.start(executable, arguments);
    } on Object catch (error) {
      return ProcessResult.failure(
        ProcessFailure.notFound(executable, error.toString()),
      );
    }

    final stdoutFuture = process.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    final stderrFuture = process.stderr
        .transform(const SystemEncoding().decoder)
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
