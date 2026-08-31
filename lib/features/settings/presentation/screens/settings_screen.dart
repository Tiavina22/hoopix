import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/theme/theme_controller.dart';
import 'package:hoopix/core/widgets/metric_card.dart';

/// App preferences. Currently holds the one control the app needs: the
/// light/dark switch, applied to [HoopixApp] in real time via
/// [themeController].
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        HoopixSpacing.xxxl,
        HoopixLayout.trafficLightInset,
        HoopixSpacing.xxxl,
        HoopixSpacing.xxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: HoopixType.largeTitle.copyWith(
              color: palette.labelPrimary,
            ),
          ),
          const SizedBox(height: HoopixSpacing.xxl),
          MetricCard(title: 'Appearance', child: _ThemeRow(themeController)),
        ],
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow(this.themeController);

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        final isDark = themeController.isDark;
        return Row(
          children: [
            Expanded(
              child: Text(
                'Dark Mode',
                style: HoopixType.body.copyWith(color: palette.labelPrimary),
              ),
            ),
            Switch(
              value: isDark,
              activeThumbColor: palette.brand,
              thumbIcon: WidgetStateProperty.resolveWith<Icon?>(
                (states) => Icon(
                  states.contains(WidgetState.selected)
                      ? Icons.nightlight_round
                      : Icons.wb_sunny_rounded,
                  size: 14,
                  color: states.contains(WidgetState.selected)
                      ? palette.brand
                      : palette.labelTertiary,
                ),
              ),
              onChanged: themeController.setDark,
            ),
          ],
        );
      },
    );
  }
}
