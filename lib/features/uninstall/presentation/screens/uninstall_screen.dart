import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/core/widgets/metric_card.dart';
import 'package:hoopix/features/uninstall/data/repositories/uninstall_inventory_repository_impl.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/entities/sibling_guard.dart';
import 'package:hoopix/features/uninstall/domain/repositories/uninstall_inventory_repository.dart';
import 'package:hoopix/features/uninstall/domain/usecases/approve_uninstall.dart';
import 'package:hoopix/features/uninstall/domain/usecases/watch_uninstall_inventory.dart';
import 'package:hoopix/features/uninstall/presentation/state/uninstall_controller.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// Installed apps, their leftover files, and their sizes. Approving what's
/// checked moves each app's bundle and its exact known leftovers to the
/// Trash — gated by a fresh live same-bundle-id sibling re-scan and fresh
/// leftover re-discovery immediately before anything is removed, never the
/// possibly-stale list this screen shows.
///
/// Launch services/login item teardown and Homebrew cask routing are not
/// part of this pass yet — each is its own separate, higher-risk port.
class UninstallScreen extends StatefulWidget {
  const UninstallScreen({super.key, this.repository, this.homePath});

  final UninstallInventoryRepository? repository;
  final String? homePath;

  @override
  State<UninstallScreen> createState() => _UninstallScreenState();
}

class _UninstallScreenState extends State<UninstallScreen> {
  late final UninstallController _controller;

  @override
  void initState() {
    super.initState();
    final home =
        widget.homePath ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final repository =
        widget.repository ?? UninstallInventoryRepositoryImpl(home: home);
    _controller = UninstallController(
      WatchUninstallInventory(repository),
      ApproveUninstall(repository),
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Nothing moves until the user confirms which apps, and only what they
  /// left checked is on offer.
  Future<void> _confirmAndUninstall() async {
    final l10n = AppLocalizations.of(context)!;
    final selected = _controller.selectedApps;
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _UninstallConfirmationDialog(
        count: selected.length,
        sizeBytes: _controller.selectedReclaimableBytes,
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final failures = await _controller.approve();
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failures.isNotEmpty
              ? l10n.uninstallTrashRefused(failures.length)
              : l10n.uninstallTrashed(selected.length),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(
          HoopixSpacing.xxxl,
          HoopixLayout.trafficLightInset,
          HoopixSpacing.xxxl,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(controller: _controller, onUninstall: _confirmAndUninstall),
            const SizedBox(height: HoopixSpacing.lg),
            Expanded(child: _Body(controller: _controller)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onUninstall});

  final UninstallController controller;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final apps = controller.apps;
    final selected = controller.selectedApps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              l10n.sectionUninstallLabel,
              style: HoopixType.largeTitle.copyWith(
                color: palette.labelPrimary,
              ),
            ),
            const SizedBox(width: HoopixSpacing.md),
            if (apps != null && apps.isNotEmpty) ...[
              _MasterCheckbox(controller: controller),
              const SizedBox(width: HoopixSpacing.xs),
              Text(
                selected.isEmpty
                    ? l10n.uninstallNoneSelected
                    : '${l10n.uninstallAppCount(selected.length)}'
                          ' · ${formatBytes(controller.selectedReclaimableBytes)}',
                style: HoopixType.callout.copyWith(
                  color: palette.labelTertiary,
                ),
              ),
            ],
            const Spacer(),
            FilledButton(
              onPressed: controller.canApprove ? onUninstall : null,
              style: FilledButton.styleFrom(
                backgroundColor: palette.brand,
                disabledBackgroundColor: palette.surfaceSubtle,
                foregroundColor: Colors.white,
                disabledForegroundColor: palette.labelTertiary,
                textStyle: HoopixType.body,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                controller.isRemoving
                    ? l10n.uninstallWorking
                    : l10n.uninstallButtonLabel,
              ),
            ),
          ],
        ),
        const SizedBox(height: HoopixSpacing.xs),
        Text(
          l10n.uninstallHint,
          style: HoopixType.callout.copyWith(color: palette.labelSecondary),
        ),
      ],
    );
  }
}

/// Tri-state checkbox for the whole list: checked when every app is
/// selected, unchecked when none are, indeterminate in between. Toggling
/// from either unchecked or indeterminate selects everything.
class _MasterCheckbox extends StatelessWidget {
  const _MasterCheckbox({required this.controller});

  final UninstallController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final apps = controller.apps ?? const [];
    final selectedCount = controller.selectedApps.length;
    final value = selectedCount == 0
        ? false
        : selectedCount == apps.length
        ? true
        : null;

    return SizedBox(
      width: 18,
      height: 18,
      child: Checkbox(
        value: value,
        tristate: true,
        activeColor: palette.brand,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        onChanged: (_) => controller.setAllSelected(value != true),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final UninstallController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    final error = controller.error;
    if (error != null) {
      return _Notice(message: l10n.uninstallFailed('$error'));
    }

    final apps = controller.apps;
    if (apps == null) {
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: palette.brand,
          ),
        ),
      );
    }

    if (apps.isEmpty && !controller.isScanning) {
      return _Notice(message: l10n.uninstallNothingFound);
    }

    final sorted = [...apps]
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: HoopixSpacing.xxxl),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: HoopixSpacing.sm),
      itemBuilder: (context, index) {
        final app = sorted[index];
        return _AppCard(
          app: app,
          controller: controller,
          hasSharedInstall: bundleIdHasSurvivingSibling(
            bundleId: app.bundleId,
            appPath: app.path,
            allApps: sorted,
            selectedPaths: {app.path},
          ),
        );
      },
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({
    required this.app,
    required this.controller,
    required this.hasSharedInstall,
  });

  final InstalledApp app;
  final UninstallController controller;
  final bool hasSharedInstall;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return MetricCard(
      title: app.displayName,
      trailing: Text(
        app.sizeBytes == null ? '—' : formatBytes(app.sizeBytes!),
        style: HoopixType.callout.copyWith(color: palette.labelTertiary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: controller.isSelected(app.path),
              activeColor: palette.brand,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onChanged: (_) => controller.toggle(app.path),
            ),
          ),
          const SizedBox(width: HoopixSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.path,
                  overflow: TextOverflow.ellipsis,
                  style: HoopixType.callout.copyWith(
                    color: palette.labelSecondary,
                  ),
                ),
                const SizedBox(height: HoopixSpacing.xs),
                Wrap(
                  spacing: HoopixSpacing.xs,
                  runSpacing: HoopixSpacing.xs,
                  children: [
                    if (app.leftoverPaths.isNotEmpty)
                      _Badge(
                        text: l10n.uninstallLeftoverCount(
                          app.leftoverPaths.length,
                        ),
                        color: palette.labelTertiary,
                      ),
                    if (hasSharedInstall)
                      _Badge(
                        text: l10n.uninstallSharedInstallBadge,
                        color: palette.brand,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(HoopixRadius.sm),
      ),
      child: Text(
        text,
        style: HoopixType.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Text(
        message,
        style: HoopixType.body.copyWith(color: palette.labelSecondary),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Names what is about to move and where it goes — Trash, not permanent
/// deletion, and recoverable from there, for every path this pass ever
/// touches.
class _UninstallConfirmationDialog extends StatelessWidget {
  const _UninstallConfirmationDialog({
    required this.count,
    required this.sizeBytes,
  });

  final int count;
  final int sizeBytes;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      backgroundColor: palette.surface,
      title: Text(
        l10n.uninstallConfirmTitle(count),
        style: HoopixType.title.copyWith(color: palette.labelPrimary),
      ),
      content: Text(
        l10n.uninstallConfirmBody(formatBytes(sizeBytes)),
        style: HoopixType.body.copyWith(color: palette.labelSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: palette.labelSecondary),
          child: Text(l10n.analyzeCancel, style: HoopixType.body),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: palette.danger),
          child: Text(l10n.uninstallButtonLabel, style: HoopixType.body),
        ),
      ],
    );
  }
}
