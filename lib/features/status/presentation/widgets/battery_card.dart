import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/core/widgets/metric_card.dart';
import 'package:hoopix/core/widgets/ring_gauge.dart';
import 'package:hoopix/core/widgets/tabular_text.dart';
import 'package:hoopix/features/status/domain/entities/battery_status.dart';
import 'package:hoopix/l10n/app_localizations.dart';

class BatteryCard extends StatelessWidget {
  const BatteryCard({super.key, required this.battery});

  final BatteryStatus? battery;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final battery = this.battery;

    return MetricCard(
      title: l10n.batteryCardTitle,
      trailing: battery != null && battery.isPluggedIn
          ? Icon(
              battery.isCharging ? Icons.bolt : Icons.power_outlined,
              size: 14,
              color: palette.brand,
            )
          : null,
      child: battery == null
          ? UnavailableNote(label: l10n.noBattery)
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
                  _subtitle(battery, l10n),
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

  String _subtitle(BatteryStatus battery, AppLocalizations l10n) {
    final state = switch (battery) {
      _ when battery.isCharging => l10n.batteryCharging,
      // Plugged in but holding — macOS does this near a full charge, and
      // calling it "On battery" would be wrong.
      _ when battery.isPluggedIn => l10n.batteryPluggedIn,
      _ => l10n.batteryOnBattery,
    };

    final remaining = battery.timeRemaining;
    if (remaining == null || remaining == Duration.zero) return state;
    return l10n.batteryStateWithRemaining(state, formatDuration(remaining));
  }
}
