/// Aggregate network counters across active, non-virtual interfaces, plus
/// the throughput computed since the previous sample (0 on the first tick).
class NetworkStatus {
  const NetworkStatus({
    required this.bytesReceived,
    required this.bytesSent,
    this.receiveRateBytesPerSecond = 0,
    this.sendRateBytesPerSecond = 0,
  });

  final int bytesReceived;
  final int bytesSent;
  final double receiveRateBytesPerSecond;
  final double sendRateBytesPerSecond;
}
