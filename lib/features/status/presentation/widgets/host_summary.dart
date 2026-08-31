import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/features/status/domain/entities/host_status.dart';

/// Machine identity line under the screen title: name, OS, uptime.
class HostSummary extends StatelessWidget {
  const HostSummary({super.key, required this.host});

  final HostStatus? host;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final host = this.host;

    final text = host == null
        ? 'Host information unavailable'
        : [
            host.hostname.replaceFirst(RegExp(r'\.local$'), ''),
            'macOS ${host.osVersion}',
            'up ${formatDuration(host.uptime)}',
          ].join('  ·  ');

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: HoopixType.body.copyWith(color: palette.labelSecondary),
    );
  }
}
