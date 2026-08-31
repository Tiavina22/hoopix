/// Machine identity and uptime, shown as the Status screen's header.
class HostStatus {
  const HostStatus({
    required this.hostname,
    required this.osVersion,
    required this.uptime,
  });

  final String hostname;
  final String osVersion;
  final Duration uptime;
}
