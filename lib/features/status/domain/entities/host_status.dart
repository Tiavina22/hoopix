/// Machine identity and uptime, shown as the Status screen's header.
class HostStatus {
  const HostStatus({
    required this.hostname,
    required this.osVersion,
    required this.uptime,
    this.model,
    this.chip,
  });

  final String hostname;
  final String osVersion;
  final Duration uptime;

  /// The Mac's model name (e.g. "MacBook Pro"), from `system_profiler`.
  /// Null when the probe fails or the field is unrecognized.
  final String? model;

  /// The chip name (e.g. "Apple M1"), or the Intel processor name as a
  /// fallback on machines with no `Chip:` line. Null under the same
  /// conditions as [model].
  final String? chip;
}
