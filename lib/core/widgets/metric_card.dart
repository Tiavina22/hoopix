import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';

/// The app's single surface primitive: a hairline-bordered panel with one
/// small uppercase title. Depth comes from the border and a barely-there
/// shadow rather than a Material elevation, which keeps the dashboard calm
/// when several cards sit side by side.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(HoopixRadius.lg),
        border: Border.all(color: palette.separator),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(HoopixSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: HoopixType.cardTitle.copyWith(
                      color: palette.labelTertiary,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: HoopixSpacing.lg),
            child,
          ],
        ),
      ),
    );
  }
}

/// Consistent treatment for a metric the engine couldn't read this tick —
/// styled as a quiet absence rather than an error, because one flaky probe
/// isn't a failure of the dashboard.
class UnavailableNote extends StatelessWidget {
  const UnavailableNote({super.key, this.label = 'Unavailable'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(Icons.remove, size: 14, color: palette.labelTertiary),
        const SizedBox(width: HoopixSpacing.sm),
        Text(
          label,
          style: HoopixType.body.copyWith(color: palette.labelTertiary),
        ),
      ],
    );
  }
}
