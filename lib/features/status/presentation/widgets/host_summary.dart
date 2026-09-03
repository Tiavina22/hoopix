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
            _modelAndChip(host.model, host.chip),
            l10n.hostMacOsVersion(host.osVersion),
            l10n.hostUpUptime(formatDuration(host.uptime)),
          ].whereType<String>().where((s) => s.isNotEmpty).join('  ·  ');

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: HoopixType.body.copyWith(color: palette.labelSecondary),
    );
  }

  /// "MacBook Pro (Apple M1)", trimmed to whichever half is known. Null
  /// when neither is, so the joined summary line doesn't gain a stray
  /// separator for a probe that returned nothing.
  static String? _modelAndChip(String? model, String? chip) {
    if (model == null && chip == null) return null;
    if (chip == null) return model;
    if (model == null) return chip;
    return '$model ($chip)';
  }
}
