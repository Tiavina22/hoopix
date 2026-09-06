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
import 'package:hoopix/features/uninstall/domain/usecases/watch_uninstall_inventory.dart';
import 'package:hoopix/features/uninstall/presentation/state/uninstall_controller.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// Installed apps, their leftover files, and their sizes — review-only for
/// now. There is deliberately no delete button here: teardown needs launch
/// services, login items, and the live sibling guard's actual gate landing
/// together as one reviewed unit, per [UninstallInventoryRepository]'s own
/// contract.
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
    _controller = UninstallController(WatchUninstallInventory(repository))
      ..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
            _Header(controller: _controller),
            const SizedBox(height: HoopixSpacing.lg),
            Expanded(child: _Body(controller: _controller)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final UninstallController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final apps = controller.apps;

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
            if (apps != null && apps.isNotEmpty) ...[
              const SizedBox(width: HoopixSpacing.md),
              Text(
                l10n.uninstallAppCount(apps.length),
                style: HoopixType.callout.copyWith(
                  color: palette.labelTertiary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: HoopixSpacing.xs),
        Text(
          l10n.uninstallReadOnlyHint,
          style: HoopixType.callout.copyWith(color: palette.labelSecondary),
        ),
      ],
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
  const _AppCard({required this.app, required this.hasSharedInstall});

  final InstalledApp app;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            app.path,
            overflow: TextOverflow.ellipsis,
            style: HoopixType.callout.copyWith(color: palette.labelSecondary),
          ),
          const SizedBox(height: HoopixSpacing.xs),
          Wrap(
            spacing: HoopixSpacing.xs,
            runSpacing: HoopixSpacing.xs,
            children: [
              if (app.leftoverPaths.isNotEmpty)
                _Badge(
                  text: l10n.uninstallLeftoverCount(app.leftoverPaths.length),
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
