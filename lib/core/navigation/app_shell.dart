import 'package:flutter/material.dart';
import 'package:hoopix/core/brand/hoopix_logo.dart';
import 'package:hoopix/core/locale/locale_controller.dart';
import 'package:hoopix/core/navigation/hoopix_section.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/theme/theme_controller.dart';
import 'package:hoopix/core/widgets/placeholder_screen.dart';
import 'package:hoopix/features/analyze/presentation/screens/analyze_screen.dart';
import 'package:hoopix/features/clean/presentation/screens/clean_screen.dart';
import 'package:hoopix/features/settings/presentation/screens/settings_screen.dart';
import 'package:hoopix/features/status/presentation/screens/status_screen.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// Sidebar + content shell. Sections with a feature module behind them
/// render it; the rest render [PlaceholderScreen] until they have one.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.themeController,
    required this.localeController,
  });

  final ThemeController themeController;
  final LocaleController localeController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  HoopixSection _selected = HoopixSection.status;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    // A Material ancestor is what gives descendants a real DefaultTextStyle.
    // Without one, Flutter paints every Text with its unstyled-text debug
    // decoration (double underlines), which is not a styling detail to work
    // around — it means the subtree has no text theme at all.
    return Material(
      color: palette.windowBackground,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            selected: _selected,
            onSelected: (section) => setState(() => _selected = section),
          ),
          Expanded(child: _content(_selected)),
        ],
      ),
    );
  }

  Widget _content(HoopixSection section) {
    return switch (section) {
      HoopixSection.analyze => const AnalyzeScreen(),
      HoopixSection.clean => const CleanScreen(),
      HoopixSection.status => const StatusScreen(),
      HoopixSection.settings => SettingsScreen(
        themeController: widget.themeController,
        localeController: widget.localeController,
      ),
      _ => PlaceholderScreen(section: section),
    };
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelected});

  final HoopixSection selected;
  final ValueChanged<HoopixSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: HoopixLayout.sidebarWidth,
      decoration: BoxDecoration(
        color: palette.sidebarBackground,
        border: Border(right: BorderSide(color: palette.separator)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Leaves room for the traffic lights floating over the sidebar.
          const SizedBox(height: HoopixLayout.trafficLightInset),
          const _Wordmark(),
          const SizedBox(height: HoopixSpacing.xl),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: HoopixSpacing.sm,
              ),
              children: [
                for (final section in HoopixSection.values)
                  _SidebarItem(
                    section: section,
                    isSelected: section == selected,
                    onTap: () => onSelected(section),
                  ),
              ],
            ),
          ),
          const _SidebarFooter(),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HoopixSpacing.lg),
      child: Row(
        children: [
          HoopixLogo(
            size: 26,
            gradient: LinearGradient(
              colors: [palette.brand, palette.brandStrong],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          const SizedBox(width: HoopixSpacing.md),
          Text(
            'Hoopix',
            style: HoopixType.title.copyWith(color: palette.labelPrimary),
          ),
        ],
      ),
    );
  }
}

/// One navigation row. Tracks hover itself so the sidebar responds to the
/// pointer the way a native Mac app does.
class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.section,
    required this.isSelected,
    required this.onTap,
  });

  final HoopixSection section;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isSelected = widget.isSelected;

    final background = isSelected
        ? palette.brandSubtle
        : _isHovered
        ? palette.separator
        : Colors.transparent;
    final foreground = isSelected ? palette.brand : palette.labelSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: HoopixSpacing.sm),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(HoopixRadius.sm + 2),
            ),
            child: Row(
              children: [
                Icon(widget.section.icon, size: 16, color: foreground),
                const SizedBox(width: HoopixSpacing.md),
                Expanded(
                  child: Text(
                    widget.section.label(AppLocalizations.of(context)!),
                    style: HoopixType.body.copyWith(
                      color: isSelected ? palette.labelPrimary : foreground,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HoopixSpacing.lg,
        HoopixSpacing.md,
        HoopixSpacing.lg,
        HoopixSpacing.lg,
      ),
      child: Text(
        l10n.openSourceFooter('0.1.0'),
        style: HoopixType.caption.copyWith(color: palette.labelTertiary),
      ),
    );
  }
}
