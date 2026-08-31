import 'package:hoopix/features/status/domain/entities/network_status.dart';

class NetworkStatusModel extends NetworkStatus {
  const NetworkStatusModel({
    required super.bytesReceived,
    required super.bytesSent,
    super.receiveRateBytesPerSecond,
    super.sendRateBytesPerSecond,
  });

  /// Interface prefixes that are loopback/virtual/tunnel noise rather than
  /// real network activity — the same set Mole's own status collector
  /// filters (`cmd/status/metrics_network.go`), used here only as a
  /// reference for which prefixes are noise on macOS.
  static const _ignoredInterfacePrefixes = [
    'lo',
    'awdl',
    'utun',
    'llw',
    'bridge',
    'gif',
    'stf',
    'xhc',
    'anpi',
    'ap',
  ];

  /// Sums Ibytes/Obytes across `netstat -ib` rows for real network
  /// interfaces. `netstat` prints one row per address family for the same
  /// interface (Link/inet/inet6); only the first (Link#) row — which always
  /// has 11 columns including a MAC address — is counted, so later
  /// duplicate rows for the same name are skipped. A row with a missing
  /// Address column (10 tokens instead of 11) is skipped rather than
  /// risking a column-shifted misread.
  factory NetworkStatusModel.fromNetstat(String netstatOutput) {
    final seen = <String>{};
    var totalIn = 0;
    var totalOut = 0;

    for (final line in netstatOutput.split('\n').skip(1)) {
      final columns = line.trim().split(RegExp(r'\s+'));
      if (columns.length != 11) continue;

      final name = columns[0];
      if (_ignoredInterfacePrefixes.any(name.startsWith) || !seen.add(name)) {
        continue;
      }

      final ibytes = int.tryParse(columns[6]);
      final obytes = int.tryParse(columns[9]);
      if (ibytes == null || obytes == null) continue;

      totalIn += ibytes;
      totalOut += obytes;
    }

    return NetworkStatusModel(bytesReceived: totalIn, bytesSent: totalOut);
  }
}
