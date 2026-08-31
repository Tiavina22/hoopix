import 'package:flutter/material.dart';
import 'package:hoopix/core/locale/locale_controller.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/theme/theme_controller.dart';
import 'package:hoopix/core/widgets/metric_card.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// App preferences: the light/dark switch and the language switch, applied
/// to [HoopixApp] in real time via [themeController] and [localeController].
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.themeController,
    required this.localeController,
  });

  final ThemeController themeController;
  final LocaleController localeController;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

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
            l10n.sectionSettingsLabel,
            style: HoopixType.largeTitle.copyWith(
              color: palette.labelPrimary,
            ),
          ),
          const SizedBox(height: HoopixSpacing.xxl),
          MetricCard(
            title: l10n.appearanceCardTitle,
            child: _ThemeRow(themeController),
          ),
          const SizedBox(height: HoopixSpacing.lg),
          MetricCard(
            title: l10n.languageCardTitle,
            child: _LanguageRow(localeController),
          ),
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
    final l10n = AppLocalizations.of(context)!;

    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        final isDark = themeController.isDark;
        return Row(
          children: [
            Expanded(
              child: Text(
                l10n.darkModeLabel,
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

/// Language names are shown in each language's own name ("English",
/// "Français") rather than translated — the standard convention for a
/// language picker, so a user who landed on the wrong language can still
/// find their way back.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow(this.localeController);

  final LocaleController localeController;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedBuilder(
      animation: localeController,
      builder: (context, _) {
        final selected = localeController.value.languageCode;
        return SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'en', label: Text('English')),
            ButtonSegment(value: 'fr', label: Text('Français')),
          ],
          selected: {selected},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              localeController.setLocale(Locale(selection.first)),
          style: SegmentedButton.styleFrom(
            backgroundColor: palette.surfaceSubtle,
            foregroundColor: palette.labelSecondary,
            selectedBackgroundColor: palette.brandSubtle,
            selectedForegroundColor: palette.brand,
            side: BorderSide(color: palette.separator),
            textStyle: HoopixType.body,
          ),
        );
      },
    );
  }
}
