import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// Display name for a row. Structural and generic overview rows are
/// translated; tool rows keep their product name ("Homebrew Cache", "Xcode
/// DerivedData"), and ordinary directory entries use their folder name.
String overviewLabel(
  AppLocalizations l10n,
  OverviewRowKind? kind,
  String fallback,
) => switch (kind) {
  OverviewRowKind.home => l10n.analyzeRowHome,
  OverviewRowKind.userLibrary => l10n.analyzeRowUserLibrary,
  OverviewRowKind.applications => l10n.analyzeRowApplications,
  OverviewRowKind.systemLibrary => l10n.analyzeRowSystemLibrary,
  OverviewRowKind.iosBackups => l10n.analyzeRowIosBackups,
  OverviewRowKind.oldDownloads => l10n.analyzeRowOldDownloads,
  OverviewRowKind.tool || null => fallback,
};
