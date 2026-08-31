import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/core/widgets/metric_card.dart';
import 'package:hoopix/core/widgets/ring_gauge.dart';
import 'package:hoopix/features/status/domain/entities/memory_status.dart';
import 'package:hoopix/l10n/app_localizations.dart';

class MemoryGauge extends StatelessWidget {
  const MemoryGauge({super.key, required this.memory});

  final MemoryStatus? memory;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final memory = this.memory;

    return MetricCard(
      title: l10n.memoryCardTitle,
      child: memory == null
          ? const UnavailableNote()
          : Row(
              children: [
                RingGauge(
                  value: memory.usedPercent / 100,
                  centerLabel: '${memory.usedPercent.round()}%',
                ),
                const SizedBox(width: HoopixSpacing.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatBytes(memory.usedBytes),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HoopixType.metric.copyWith(
                          fontSize: 20,
                          color: palette.labelPrimary,
                        ),
                      ),
                      const SizedBox(height: HoopixSpacing.xs),
                      Text(
                        l10n.memoryOfTotalUsed(formatBytes(memory.totalBytes)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HoopixType.callout.copyWith(
                          color: palette.labelSecondary,
                        ),
                      ),
                      const SizedBox(height: HoopixSpacing.md),
                      Text(
                        l10n.memoryFree(formatBytes(memory.freeBytes)),
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
