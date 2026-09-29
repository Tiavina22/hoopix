/// Why an external process call did not produce usable output. Callers that
/// only report the failure read [reason]; callers that must *branch* on it —
/// Analyze has to tell "gave up waiting" apart from "finished with errors but
/// still printed a usable total" — read [kind].
enum ProcessFailureKind { notFound, timedOut, nonZeroExit }

/// A typed reason an external process call did not produce output, so
/// datasources can degrade gracefully instead of throwing raw exceptions.
class ProcessFailure {
  const ProcessFailure._(
    this.executable,
    this.kind,
    this.reason, {
    this.exitCode,
    this.stderr,
  });

  factory ProcessFailure.notFound(String executable, String detail) =>
      ProcessFailure._(
        executable,
        ProcessFailureKind.notFound,
        'not found: $detail',
      );

  factory ProcessFailure.timedOut(String executable, Duration timeout) =>
      ProcessFailure._(
        executable,
        ProcessFailureKind.timedOut,
        'timed out after ${timeout.inSeconds}s',
      );

  factory ProcessFailure.nonZeroExit(
    String executable,
    int exitCode,
    String stderr,
  ) => ProcessFailure._(
    executable,
    ProcessFailureKind.nonZeroExit,
    'exited $exitCode: ${stderr.trim()}',
    exitCode: exitCode,
    stderr: stderr,
  );

  final String executable;
  final ProcessFailureKind kind;
  final String reason;

  /// Only set for [ProcessFailureKind.nonZeroExit] — the process's own exit
  /// code, for a caller that must branch on the exact value (`pgrep`'s 1
  /// means "confirmed no match", not an error) rather than parse [reason].
  final int? exitCode;

  /// Only set for [ProcessFailureKind.nonZeroExit] — the process's raw
  /// stderr, for a caller whose verdict depends on whether the tool said
  /// anything at all (`lsof`'s exit 1 is "nothing open" only when it is
  /// silent; with diagnostics it is an incomplete answer).
  final String? stderr;

  @override
  String toString() => '$executable $reason';
}
