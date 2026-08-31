import 'package:flutter/material.dart';
import 'package:hoopix/core/navigation/hoopix_section.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// Shown for every [HoopixSection] that doesn't have a real feature module
/// yet. Intentionally inert — no scanning, no filesystem access.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.section});

  final HoopixSection section;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: palette.brandSubtle,
              borderRadius: BorderRadius.circular(HoopixRadius.lg),
            ),
            child: Icon(section.icon, size: 28, color: palette.brand),
          ),
          const SizedBox(height: HoopixSpacing.xl),
          Text(
            section.label(l10n),
            style: HoopixType.title.copyWith(color: palette.labelPrimary),
          ),
          const SizedBox(height: HoopixSpacing.xs),
          Text(
            section.description(l10n),
            style: HoopixType.body.copyWith(color: palette.labelSecondary),
          ),
          const SizedBox(height: HoopixSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: HoopixSpacing.md,
              vertical: HoopixSpacing.xs + 2,
            ),
            decoration: BoxDecoration(
              color: palette.surfaceSubtle,
              borderRadius: BorderRadius.circular(HoopixRadius.pill),
              border: Border.all(color: palette.separator),
            ),
            child: Text(
              l10n.comingSoon,
              style: HoopixType.caption.copyWith(color: palette.labelSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
