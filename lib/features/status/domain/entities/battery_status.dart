/// The machine's internal battery. Absent entirely (null upstream) on
/// desktop Macs, which is a normal state, not a failure.
///
/// [isCharging] and [isPluggedIn] are separate because they genuinely differ:
/// a Mac at 95% on AC power is plugged in but deliberately not charging, and
/// reporting that as "on battery" would be wrong.
class BatteryStatus {
  const BatteryStatus({
    required this.percent,
    required this.isCharging,
    required this.isPluggedIn,
    this.timeRemaining,
  });

  final int percent;
  final bool isCharging;
  final bool isPluggedIn;
  final Duration? timeRemaining;
}
