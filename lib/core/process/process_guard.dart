import 'process_failure.dart';
import 'process_runner.dart';

/// Whether a process is running, port of Mole's `mole_pgrep_any` tri-state
/// (`lib/core/base.sh`): a probe that cannot conclusively rule a process
/// out must never be read as "not running" — that gap is exactly what
/// would let a live process's own data be deleted out from under it.
enum ProcessLiveness { running, notRunning, unknown }

/// Answers "is this process running" for cleanup targets that must not be
/// touched while their owning app is active — Xcode DerivedData, a
/// browser's profile Code Cache, and the rest of the deferred targets each
/// section's own comments name.
///
/// [check] mirrors `mole_pgrep_any -x NAME -f PATTERN ...`: any match
/// (`-x` exact process name, `-f` full-command-line substring) means
/// running: any check that could not be trusted — `pgrep` missing, an
/// unexpected exit code — means unknown, never silently "not running".
class ProcessGuard {
  const ProcessGuard(this._probe);

  final ProcessRunner _probe;

  Future<ProcessLiveness> check({
    List<String> exactNames = const [],
    List<String> patterns = const [],
  }) async {
    if (exactNames.isEmpty && patterns.isEmpty) return ProcessLiveness.unknown;

    var sawUnknown = false;
    for (final name in exactNames) {
      final liveness = await _pgrep(['-x', name]);
      if (liveness == ProcessLiveness.running) return liveness;
      if (liveness == ProcessLiveness.unknown) sawUnknown = true;
    }
    for (final pattern in patterns) {
      final liveness = await _pgrep(['-f', pattern]);
      if (liveness == ProcessLiveness.running) return liveness;
      if (liveness == ProcessLiveness.unknown) sawUnknown = true;
    }
    return sawUnknown ? ProcessLiveness.unknown : ProcessLiveness.notRunning;
  }

  Future<ProcessLiveness> _pgrep(List<String> arguments) async {
    final result = await _probe.run('pgrep', arguments);
    if (result.isSuccess) return ProcessLiveness.running;

    final failure = result.failure;
    // pgrep's own contract: exit 1 is the confirmed "no match" answer,
    // everything else (2 = usage error, 127 = not found, a timeout, ...) is
    // a probe that could not be trusted.
    final confirmedNoMatch =
        failure != null &&
        failure.kind == ProcessFailureKind.nonZeroExit &&
        failure.exitCode == 1;
    return confirmedNoMatch
        ? ProcessLiveness.notRunning
        : ProcessLiveness.unknown;
  }
}
