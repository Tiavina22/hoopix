import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/core/widgets/metric_card.dart';
import 'package:hoopix/core/widgets/ring_gauge.dart';
import 'package:hoopix/core/widgets/tabular_text.dart';
import 'package:hoopix/features/status/domain/entities/disk_status.dart';

class DiskList extends StatelessWidget {
  const DiskList({super.key, required this.disks});

  final List<DiskStatus> disks;

  @override
  Widget build(BuildContext context) {
    return MetricCard(
      title: 'Storage',
      child: disks.isEmpty
          ? const UnavailableNote()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, disk) in disks.indexed) ...[
                  if (index > 0) const SizedBox(height: HoopixSpacing.lg),
                  _DiskRow(disk: disk),
                ],
              ],
            ),
    );
  }
}

class _DiskRow extends StatelessWidget {
  const _DiskRow({required this.disk});

  final DiskStatus disk;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fraction = disk.usedPercent / 100;
    // Storage is the one metric where "nearly full" is actionable, so it
    // uses the threshold palette rather than the brand color.
    final color = palette.meterColor(fraction);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _displayName(disk.mountPoint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HoopixType.headline.copyWith(
                  color: palette.labelPrimary,
                ),
              ),
            ),
            const SizedBox(width: HoopixSpacing.sm),
            TabularText(
              '${disk.usedPercent.round()}%',
              style: HoopixType.numeric.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: HoopixSpacing.sm),
        LinearMeter(value: fraction, color: color),
        const SizedBox(height: HoopixSpacing.sm),
        Text(
          '${formatBytes(disk.availableBytes)} free of ${formatBytes(disk.totalBytes)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: HoopixType.caption.copyWith(color: palette.labelTertiary),
        ),
      ],
    );
  }

  /// Friendly volume label. The boot volume is called "Startup disk" rather
  /// than guessing at its name, which the user may well have changed.
  String _displayName(String mountPoint) {
    if (mountPoint == '/') return 'Startup disk';
    if (mountPoint.startsWith('/Volumes/')) {
      return mountPoint.substring('/Volumes/'.length);
    }
    return mountPoint;
  }
}
