import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/widgets/metric_card.dart';
import 'package:hoopix/core/widgets/ring_gauge.dart';
import 'package:hoopix/core/widgets/tabular_text.dart';
import 'package:hoopix/features/status/domain/entities/cpu_status.dart';

class CpuGauge extends StatelessWidget {
  const CpuGauge({super.key, required this.cpu});

  final CpuStatus? cpu;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cpu = this.cpu;

    return MetricCard(
      title: 'CPU',
      child: cpu == null
          ? const UnavailableNote()
          : Row(
              children: [
                RingGauge(
                  value: cpu.usedPercent / 100,
                  centerLabel: '${cpu.usedPercent.round()}%',
                ),
                const SizedBox(width: HoopixSpacing.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Breakdown(
                        label: 'User',
                        value: '${cpu.userPercent.toStringAsFixed(1)}%',
                      ),
                      const SizedBox(height: HoopixSpacing.sm),
                      _Breakdown(
                        label: 'System',
                        value: '${cpu.systemPercent.toStringAsFixed(1)}%',
                      ),
                      const SizedBox(height: HoopixSpacing.sm),
                      _Breakdown(
                        label: 'Idle',
                        value: '${cpu.idlePercent.toStringAsFixed(1)}%',
                      ),
                      const SizedBox(height: HoopixSpacing.md),
                      Text(
                        '${cpu.physicalCores} cores',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HoopixType.caption.copyWith(
                          color: palette.labelTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// One "label ......... value" row, with the value right-aligned in tabular
/// figures so the column stays steady as numbers change.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HoopixType.callout.copyWith(color: palette.labelSecondary),
          ),
        ),
        TabularText(
          value,
          style: HoopixType.numeric.copyWith(color: palette.labelPrimary),
        ),
      ],
    );
  }
}
