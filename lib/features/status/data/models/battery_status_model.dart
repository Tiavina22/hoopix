import 'package:hoopix/features/status/domain/entities/battery_status.dart';

class BatteryStatusModel extends BatteryStatus {
  const BatteryStatusModel({
    required super.percent,
    required super.isCharging,
    required super.isPluggedIn,
    super.timeRemaining,
  });

  /// `pmset -g batt` prints a power-source line followed by one line per
  /// battery, e.g.:
  ///
  /// ```
  /// Now drawing from 'AC Power'
  ///  -InternalBattery-0 (id=22413411)	95%; AC attached; not charging present: true
  /// ```
  ///
  /// The status field is read as free text rather than matched against a
  /// closed set of words. macOS uses at least `charging`, `discharging`,
  /// `charged`, `finishing charge`, `AC attached`, and `not charging`, and an
  /// unlisted one must not make a present battery look absent.
  ///
  /// Returns null only when there is no battery line at all — a desktop Mac,
  /// which is a normal state rather than a failure.
  static BatteryStatusModel? tryParse(String pmsetOutput) {
    final percentMatch = RegExp(r'(\d{1,3})%;').firstMatch(pmsetOutput);
    if (percentMatch == null) return null;

    final statusMatch = RegExp(
      r'\d{1,3}%;\s*([^;]+?)\s*(?:;|$)',
      multiLine: true,
    ).firstMatch(pmsetOutput);
    final status = statusMatch?.group(1)?.toLowerCase() ?? '';

    // "discharging" contains "charging", so match the status exactly rather
    // than by substring.
    final isCharging = status == 'charging' || status == 'finishing charge';
    final isPluggedIn =
        isCharging ||
        pmsetOutput.contains("'AC Power'") ||
        status == 'ac attached' ||
        status == 'charged';

    final remainingMatch = RegExp(
      r'(\d+):(\d{2})\s+remaining',
    ).firstMatch(pmsetOutput);
    Duration? remaining;
    if (remainingMatch != null) {
      remaining = Duration(
        hours: int.parse(remainingMatch.group(1)!),
        minutes: int.parse(remainingMatch.group(2)!),
      );
    }

    return BatteryStatusModel(
      percent: int.parse(percentMatch.group(1)!),
      isCharging: isCharging,
      isPluggedIn: isPluggedIn,
      timeRemaining: remaining,
    );
  }
}
