import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/features/status/domain/entities/host_status.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// Machine identity line under the screen title: name, OS, uptime.
class HostSummary extends StatelessWidget {
  const HostSummary({super.key, required this.host});

  final HostStatus? host;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final host = this.host;

    final text = host == null
        ? l10n.hostInfoUnavailable
        : [
            host.hostname.replaceFirst(RegExp(r'\.local$'), ''),
            l10n.hostMacOsVersion(host.osVersion),
            l10n.hostUpUptime(formatDuration(host.uptime)),
          ].join('  ·  ');

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: HoopixType.body.copyWith(color: palette.labelSecondary),
    );
  }
}
