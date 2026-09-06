import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/core/widgets/metric_card.dart';
import 'package:hoopix/features/purge/data/repositories/purge_repository_impl.dart';
import 'package:hoopix/features/purge/domain/entities/purge_activity.dart';
import 'package:hoopix/features/purge/domain/entities/purge_plan.dart';
import 'package:hoopix/features/purge/domain/repositories/purge_repository.dart';
import 'package:hoopix/features/purge/domain/usecases/approve_purge_plan.dart';
import 'package:hoopix/features/purge/domain/usecases/watch_purge_plan.dart';
import 'package:hoopix/features/purge/presentation/state/purge_controller.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// Rebuildable project build artifacts (`node_modules`, `target`,
/// `DerivedData`, ...) found on disk, before anything is removed.
///
/// Unlike Clean, approving here deletes permanently — purge's own targets
/// are rebuildable by their owning tool, not user data, so there is no
/// Trash step to offer, and the screen says so plainly rather than
/// implying anything can be put back.
class PurgeScreen extends StatefulWidget {
  const PurgeScreen({super.key, this.repository, this.homePath});

  final PurgeRepository? repository;
  final String? homePath;

  @override
  State<PurgeScreen> createState() => _PurgeScreenState();
}

class _PurgeScreenState extends State<PurgeScreen> {
  late final PurgeController _controller;

  @override
  void initState() {
    super.initState();
    final home =
        widget.homePath ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final repository = widget.repository ?? PurgeRepositoryImpl(home: home);
    _controller = PurgeController(
      WatchPurgePlan(repository),
      ApprovePurgePlan(repository),
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmAndPurge() async {
    final l10n = AppLocalizations.of(context)!;
    final selected = _controller.selected;
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _PurgeConfirmationDialog(
        count: selected.length,
        sizeBytes: _controller.selectedReclaimableBytes,
        hasCloudSynced: _controller.selectedHasCloudSynced,
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
              ? l10n.purgeRefused(failures.length)
              : l10n.purgeCleared(selected.length),
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
            _Header(controller: _controller, onPurge: _confirmAndPurge),
            const SizedBox(height: HoopixSpacing.lg),
            Expanded(child: _Body(controller: _controller)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onPurge});

  final PurgeController controller;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final plan = controller.plan;
    final selected = controller.selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              l10n.sectionPurgeLabel,
              style: HoopixType.largeTitle.copyWith(
                color: palette.labelPrimary,
              ),
            ),
            const SizedBox(width: HoopixSpacing.md),
            if (plan != null && plan.candidates.isNotEmpty) ...[
              _MasterCheckbox(controller: controller),
              const SizedBox(width: HoopixSpacing.xs),
              Text(
                selected.isEmpty
                    ? l10n.purgeNoneSelected
                    : '${l10n.purgeItemCount(selected.length)}'
                          ' · ${formatBytes(controller.selectedReclaimableBytes)}',
                style: HoopixType.callout.copyWith(
                  color: palette.labelTertiary,
                ),
              ),
            ],
            const Spacer(),
            FilledButton(
              onPressed: controller.canApprove ? onPurge : null,
              style: FilledButton.styleFrom(
                backgroundColor: palette.danger,
                disabledBackgroundColor: palette.surfaceSubtle,
                foregroundColor: Colors.white,
                disabledForegroundColor: palette.labelTertiary,
                textStyle: HoopixType.body,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                controller.isRemoving
                    ? l10n.purgeWorking
                    : l10n.purgeDeleteButton,
              ),
            ),
          ],
        ),
        const SizedBox(height: HoopixSpacing.xs),
        Text(
          l10n.purgeIrreversibleHint,
          style: HoopixType.callout.copyWith(color: palette.labelSecondary),
        ),
      ],
    );
  }
}

class _MasterCheckbox extends StatelessWidget {
  const _MasterCheckbox({required this.controller});

  final PurgeController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final all = controller.plan?.candidates ?? const [];
    final selectedCount = controller.selected.length;
    final value = selectedCount == 0
        ? false
        : selectedCount == all.length
        ? true
        : null;

    return SizedBox(
      width: 18,
      height: 18,
      child: Checkbox(
        value: value,
        tristate: true,
        activeColor: palette.danger,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        onChanged: (_) => controller.setAllSelected(value != true),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final PurgeController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    final error = controller.error;
    if (error != null) {
      return _Notice(message: l10n.purgeFailed('$error'));
    }

    final plan = controller.plan;
    if (plan == null) {
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: palette.danger,
          ),
        ),
      );
    }

    if (plan.candidates.isEmpty && !controller.isScanning) {
      return _Notice(message: l10n.purgeNothingToDo);
    }

    final bySearchRoot = <String, List<PurgeCandidate>>{};
    for (final candidate in plan.candidates) {
      bySearchRoot.putIfAbsent(candidate.searchRoot, () => []).add(candidate);
    }
    final groups = bySearchRoot.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: HoopixSpacing.xxxl),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: HoopixSpacing.lg),
      itemBuilder: (context, index) {
        final group = groups[index];
        return _RootCard(
          root: group.key,
          candidates: group.value,
          controller: controller,
        );
      },
    );
  }
}

class _RootCard extends StatelessWidget {
  const _RootCard({
    required this.root,
    required this.candidates,
    required this.controller,
  });

  final String root;
  final List<PurgeCandidate> candidates;
  final PurgeController controller;

  @override
  Widget build(BuildContext context) {
    final total = candidates.fold<int>(0, (sum, c) => sum + (c.sizeBytes ?? 0));

    return MetricCard(
      title: root.split('/').last,
      trailing: Text(
        formatBytes(total),
        style: HoopixType.callout.copyWith(
          color: context.palette.labelTertiary,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final candidate in candidates)
            _CandidateRow(candidate: candidate, controller: controller),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.candidate, required this.controller});

  final PurgeCandidate candidate;
  final PurgeController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HoopixSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: controller.isSelected(candidate.path),
              activeColor: palette.danger,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onChanged: (_) => controller.toggle(candidate.path),
            ),
          ),
          const SizedBox(width: HoopixSpacing.sm),
          Expanded(
            child: Text(
              _displayPath,
              overflow: TextOverflow.ellipsis,
              style: HoopixType.callout.copyWith(color: palette.labelPrimary),
            ),
          ),
          if (candidate.activity == PurgeActivityState.recent) ...[
            _Badge(text: l10n.purgeRecentBadge, color: palette.warning),
            const SizedBox(width: HoopixSpacing.xs),
          ] else if (candidate.activity == PurgeActivityState.uncertain) ...[
            _Badge(
              text: l10n.purgeUncertainBadge,
              color: palette.labelTertiary,
            ),
            const SizedBox(width: HoopixSpacing.xs),
          ],
          if (candidate.isCloudSynced) ...[
            _Badge(text: l10n.purgeCloudBadge, color: palette.brand),
            const SizedBox(width: HoopixSpacing.xs),
          ],
          Text(
            candidate.sizeBytes == null
                ? '—'
                : formatBytes(candidate.sizeBytes!),
            style: HoopixType.callout.copyWith(color: palette.labelTertiary),
          ),
        ],
      ),
    );
  }

  /// The path relative to its own search root — the root card's own title
  /// already names the project, so repeating that prefix on every row
  /// would only add noise.
  String get _displayPath {
    final root = candidate.searchRoot;
    return candidate.path.startsWith('$root/')
        ? candidate.path.substring(root.length + 1)
        : candidate.path;
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

class _PurgeConfirmationDialog extends StatelessWidget {
  const _PurgeConfirmationDialog({
    required this.count,
    required this.sizeBytes,
    required this.hasCloudSynced,
  });

  final int count;
  final int sizeBytes;
  final bool hasCloudSynced;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = context.palette;

    return AlertDialog(
      title: Text(l10n.purgeConfirmTitle(count)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.purgeConfirmBody(formatBytes(sizeBytes))),
          if (hasCloudSynced) ...[
            const SizedBox(height: HoopixSpacing.sm),
            Text(
              l10n.purgeCloudSyncWarning,
              style: TextStyle(color: palette.warning),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: palette.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.purgeDeleteButton),
        ),
      ],
    );
  }
}
