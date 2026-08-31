import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/core/widgets/metric_card.dart';
import 'package:hoopix/core/widgets/ring_gauge.dart';
import 'package:hoopix/core/widgets/tabular_text.dart';
import 'package:hoopix/features/status/domain/entities/battery_status.dart';

class BatteryCard extends StatelessWidget {
  const BatteryCard({super.key, required this.battery});

  final BatteryStatus? battery;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final battery = this.battery;

    return MetricCard(
      title: 'Battery',
      trailing: battery != null && battery.isPluggedIn
          ? Icon(
              battery.isCharging ? Icons.bolt : Icons.power_outlined,
              size: 14,
              color: palette.brand,
            )
          : null,
      child: battery == null
          ? const UnavailableNote(label: 'No battery')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    TabularText(
                      '${battery.percent}',
                      style: HoopixType.metric.copyWith(
                        color: palette.labelPrimary,
                      ),
                    ),
                    Text(
                      '%',
                      style: HoopixType.title.copyWith(
                        color: palette.labelTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: HoopixSpacing.md),
                LinearMeter(
                  value: battery.percent / 100,
                  // Low battery is genuinely actionable, so it earns the
                  // threshold palette instead of the brand color.
                  color: battery.percent <= 20
                      ? palette.danger
                      : palette.brand,
                ),
                const SizedBox(height: HoopixSpacing.md),
                Text(
                  _subtitle(battery),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HoopixType.caption.copyWith(
                    color: palette.labelTertiary,
                  ),
                ),
              ],
            ),
    );
  }

  String _subtitle(BatteryStatus battery) {
    final state = switch (battery) {
      _ when battery.isCharging => 'Charging',
      // Plugged in but holding — macOS does this near a full charge, and
      // calling it "On battery" would be wrong.
      _ when battery.isPluggedIn => 'Plugged in',
      _ => 'On battery',
    };

    final remaining = battery.timeRemaining;
    if (remaining == null || remaining == Duration.zero) return state;
    return '$state · ${formatDuration(remaining)} remaining';
  }
}
