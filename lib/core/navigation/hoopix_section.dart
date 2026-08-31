import 'package:flutter/material.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// The six capabilities Mole offers, plus Settings; hoopix mirrors the same
/// shape. Only [HoopixSection.status] and [HoopixSection.settings] have a
/// real feature behind them today — the rest route to a shared placeholder
/// until each gets its own feature module.
///
/// Icons are picked as one coherent outlined set (the closest Material has to
/// SF Symbols) so the sidebar reads as a family rather than a grab bag.
enum HoopixSection {
  clean(Icons.auto_awesome_outlined),
  uninstall(Icons.delete_outline),
  optimize(Icons.bolt_outlined),
  analyze(Icons.pie_chart_outline),
  status(Icons.speed_outlined),
  purge(Icons.folder_delete_outlined),
  settings(Icons.settings_outlined);

  const HoopixSection(this.icon);

  final IconData icon;

  bool get isImplemented =>
      this == HoopixSection.analyze ||
      this == HoopixSection.status ||
      this == HoopixSection.settings;
}

/// Label/description are locale-dependent, so they can't live on the enum
/// itself (a `const` constructor can't see [AppLocalizations]) — this reads
/// them from the current [AppLocalizations] instead.
extension HoopixSectionL10n on HoopixSection {
  String label(AppLocalizations l10n) => switch (this) {
    HoopixSection.clean => l10n.sectionCleanLabel,
    HoopixSection.uninstall => l10n.sectionUninstallLabel,
    HoopixSection.optimize => l10n.sectionOptimizeLabel,
    HoopixSection.analyze => l10n.sectionAnalyzeLabel,
    HoopixSection.status => l10n.sectionStatusLabel,
    HoopixSection.purge => l10n.sectionPurgeLabel,
    HoopixSection.settings => l10n.sectionSettingsLabel,
  };

  String description(AppLocalizations l10n) => switch (this) {
    HoopixSection.clean => l10n.sectionCleanDescription,
    HoopixSection.uninstall => l10n.sectionUninstallDescription,
    HoopixSection.optimize => l10n.sectionOptimizeDescription,
    HoopixSection.analyze => l10n.sectionAnalyzeDescription,
    HoopixSection.status => l10n.sectionStatusDescription,
    HoopixSection.purge => l10n.sectionPurgeDescription,
    HoopixSection.settings => l10n.sectionSettingsDescription,
  };
}
