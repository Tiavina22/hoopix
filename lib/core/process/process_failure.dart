/// A typed reason an external process call did not produce output, so
/// datasources can degrade gracefully instead of throwing raw exceptions.
class ProcessFailure {
  const ProcessFailure._(this.executable, this.reason);

  factory ProcessFailure.notFound(String executable, String detail) =>
      ProcessFailure._(executable, 'not found: $detail');

  factory ProcessFailure.timedOut(String executable, Duration timeout) =>
      ProcessFailure._(executable, 'timed out after ${timeout.inSeconds}s');

  factory ProcessFailure.nonZeroExit(
    String executable,
    int exitCode,
    String stderr,
  ) => ProcessFailure._(executable, 'exited $exitCode: ${stderr.trim()}');

  final String executable;
  final String reason;

  @override
  String toString() => '$executable $reason';
}
