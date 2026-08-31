import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/core/widgets/metric_card.dart';
import 'package:hoopix/core/widgets/tabular_text.dart';
import 'package:hoopix/features/status/domain/entities/network_status.dart';

class NetworkCard extends StatelessWidget {
  const NetworkCard({super.key, required this.network});

  final NetworkStatus? network;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final network = this.network;

    return MetricCard(
      title: 'Network',
      child: network == null
          ? const UnavailableNote()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Throughput(
                  icon: Icons.arrow_downward,
                  rate: network.receiveRateBytesPerSecond,
                  total: network.bytesReceived,
                ),
                const SizedBox(height: HoopixSpacing.md),
                _Throughput(
                  icon: Icons.arrow_upward,
                  rate: network.sendRateBytesPerSecond,
                  total: network.bytesSent,
                ),
                const SizedBox(height: HoopixSpacing.md),
                Text(
                  'Since boot',
                  style: HoopixType.caption.copyWith(
                    color: palette.labelTertiary,
                  ),
                ),
              ],
            ),
    );
  }
}

class _Throughput extends StatelessWidget {
  const _Throughput({
    required this.icon,
    required this.rate,
    required this.total,
  });

  final IconData icon;
  final double rate;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Icon(icon, size: 13, color: palette.labelTertiary),
        const SizedBox(width: HoopixSpacing.sm),
        Expanded(
          child: TabularText(
            formatByteRate(rate),
            style: HoopixType.numeric.copyWith(color: palette.labelPrimary),
          ),
        ),
        TabularText(
          formatBytes(total),
          style: HoopixType.numericCaption.copyWith(
            color: palette.labelTertiary,
          ),
        ),
      ],
    );
  }
}
