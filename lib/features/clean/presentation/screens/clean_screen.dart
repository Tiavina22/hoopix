import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/core/widgets/metric_card.dart';
import 'package:hoopix/features/clean/data/repositories/clean_repository_impl.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/repositories/clean_repository.dart';
import 'package:hoopix/features/clean/domain/usecases/approve_clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/watch_clean_plan.dart';
import 'package:hoopix/features/clean/presentation/state/clean_controller.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// What a clean run would remove, before it removes anything.
///
/// The preview is the screen. Nothing here deletes yet — approving the plan
/// is the next step, and it should be a deliberate one.
class CleanScreen extends StatefulWidget {
  const CleanScreen({super.key, this.repository, this.homePath});

  final CleanRepository? repository;
  final String? homePath;

  @override
  State<CleanScreen> createState() => _CleanScreenState();
}

class _CleanScreenState extends State<CleanScreen> {
  late final CleanController _controller;

  @override
  void initState() {
    super.initState();
    final home =
        widget.homePath ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final repository = widget.repository ?? CleanRepositoryImpl(home: home);
    _controller = CleanController(
      WatchCleanPlan(repository),
      ApproveCleanPlan(repository),
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Nothing moves until the user confirms how much, and where it goes —
  /// and only what they left checked is on offer.
  Future<void> _confirmAndClean() async {
    final l10n = AppLocalizations.of(context)!;
    final selected = _controller.selectedEligible;
    if (selected.isEmpty) return;

    final irreversibleCount = _controller.selectedIrreversibleCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _CleanConfirmationDialog(
        count: selected.length,
        sizeBytes: _controller.selectedReclaimableBytes,
        irreversibleCount: irreversibleCount,
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
              ? l10n.cleanTrashRefused(failures.length)
              : irreversibleCount > 0
              ? l10n.cleanCleared(selected.length)
              : l10n.cleanTrashed(selected.length),
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
            _Header(controller: _controller, onClean: _confirmAndClean),
            const SizedBox(height: HoopixSpacing.lg),
            Expanded(child: _Body(controller: _controller)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onClean});

  final CleanController controller;
  final VoidCallback onClean;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final plan = controller.plan;
    final selected = controller.selectedEligible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              l10n.sectionCleanLabel,
              style: HoopixType.largeTitle.copyWith(
                color: palette.labelPrimary,
              ),
            ),
            const SizedBox(width: HoopixSpacing.md),
            if (plan != null && plan.eligible.isNotEmpty) ...[
              _MasterCheckbox(controller: controller),
              const SizedBox(width: HoopixSpacing.xs),
              Text(
                selected.isEmpty
                    ? l10n.cleanNoneSelected
                    : '${l10n.cleanItemCount(selected.length)}'
                          ' · ${formatBytes(controller.selectedReclaimableBytes)}',
                style: HoopixType.callout.copyWith(
                  color: palette.labelTertiary,
                ),
              ),
            ],
            const Spacer(),
            FilledButton(
              onPressed: controller.canApprove ? onClean : null,
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
                    ? l10n.cleanWorking
                    : controller.selectedIrreversibleCount > 0
                    ? l10n.cleanCleanUp
                    : l10n.cleanMoveToTrash,
              ),
            ),
          ],
        ),
        const SizedBox(height: HoopixSpacing.xs),
        Text(
          // Says plainly that looking is not doing.
          l10n.cleanPreviewOnly,
          style: HoopixType.callout.copyWith(color: palette.labelSecondary),
        ),
      ],
    );
  }
}

/// Tri-state checkbox for the whole plan: checked when everything eligible
/// is selected, unchecked when nothing is, indeterminate in between.
/// Toggling from either unchecked or indeterminate selects everything.
class _MasterCheckbox extends StatelessWidget {
  const _MasterCheckbox({required this.controller});

  final CleanController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final eligible = controller.plan?.eligible ?? const [];
    final selectedCount = controller.selectedEligible.length;
    final value = selectedCount == 0
        ? false
        : selectedCount == eligible.length
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

  final CleanController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    final error = controller.error;
    if (error != null) {
      return _Notice(message: l10n.cleanFailed('$error'));
    }

    final plan = controller.plan;
    if (plan == null) {
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

    if (plan.eligible.isEmpty && !controller.isScanning) {
      return _Notice(message: l10n.cleanNothingToDo);
    }

    final sections = plan.bySection.entries.toList();

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: HoopixSpacing.xxxl),
      itemCount: sections.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: HoopixSpacing.lg),
      itemBuilder: (context, index) {
        if (index == sections.length) return _KeptCard(plan: plan);
        final section = sections[index];
        return _SectionCard(
          title: section.key,
          candidates: section.value,
          controller: controller,
        );
      },
    );
  }
}

class _SectionCard extends StatefulWidget {
  const _SectionCard({
    required this.title,
    required this.candidates,
    required this.controller,
  });

  final String title;
  final List<CleanCandidate> candidates;
  final CleanController controller;

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final candidates = widget.candidates;
    final total = candidates.fold<int>(0, (sum, c) => sum + (c.sizeBytes ?? 0));
    final shown = _expanded
        ? candidates
        : candidates.take(_shownPerSection).toList();
    final hiddenCount = candidates.length - shown.length;

    return MetricCard(
      title: widget.title,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SectionCheckbox(
            section: widget.title,
            candidates: candidates,
            controller: widget.controller,
          ),
          const SizedBox(width: HoopixSpacing.xs),
          Text(
            formatBytes(total),
            style: HoopixType.numericCaption.copyWith(
              color: palette.labelSecondary,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final candidate in shown)
            _CandidateRow(candidate: candidate, controller: widget.controller),
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: HoopixSpacing.sm),
              child: InkWell(
                onTap: () => setState(() => _expanded = true),
                child: Text(
                  l10n.cleanAndMore(hiddenCount),
                  style: HoopixType.caption.copyWith(
                    color: palette.labelTertiary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Enough to show what a section is about without turning the preview into
  /// a file listing; "and N more" expands to show and select the rest.
  static const _shownPerSection = 8;
}

/// Tri-state checkbox for one section: checked when every candidate in it
/// is selected, unchecked when none are, indeterminate in between.
class _SectionCheckbox extends StatelessWidget {
  const _SectionCheckbox({
    required this.section,
    required this.candidates,
    required this.controller,
  });

  final String section;
  final List<CleanCandidate> candidates;
  final CleanController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selectedCount = candidates
        .where((c) => controller.isSelected(c.path))
        .length;
    final value = selectedCount == 0
        ? false
        : selectedCount == candidates.length
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
        onChanged: (_) => controller.setSectionSelected(section, value != true),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.candidate, required this.controller});

  final CleanCandidate candidate;
  final CleanController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final size = candidate.sizeBytes;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: controller.isSelected(candidate.path),
              activeColor: palette.brand,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onChanged: (_) => controller.toggle(candidate.path),
            ),
          ),
          const SizedBox(width: HoopixSpacing.sm),
          Expanded(
            child: Text(
              candidate.path.split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HoopixType.body.copyWith(color: palette.labelPrimary),
            ),
          ),
          const SizedBox(width: HoopixSpacing.md),
          Text(
            size == null ? l10n.analyzeEntryUnknownSize : formatBytes(size),
            style: HoopixType.numericCaption.copyWith(
              color: palette.labelSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// What was left alone and why. Shown rather than hidden: a cleanup tool
/// that quietly skips things is one you cannot check.
class _KeptCard extends StatelessWidget {
  const _KeptCard({required this.plan});

  final CleanPlan plan;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    if (plan.skipped.isEmpty) return const SizedBox.shrink();

    final reasons = <(CleanSkipReason, String)>[
      (CleanSkipReason.protected, l10n.cleanKeptProtected),
      (CleanSkipReason.whitelisted, l10n.cleanKeptWhitelisted),
      (CleanSkipReason.compiledModelCache, l10n.cleanKeptModelCache),
    ];

    return MetricCard(
      title: l10n.cleanKeptTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (reason, label) in reasons)
            if (plan.skippedFor(reason) > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: HoopixType.body.copyWith(
                          color: palette.labelSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '${plan.skippedFor(reason)}',
                      style: HoopixType.numericCaption.copyWith(
                        color: palette.labelTertiary,
                      ),
                    ),
                  ],
                ),
              ),
        ],
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
      ),
    );
  }
}

/// Names how much is about to move and where it goes. "Move to Trash", not
/// "Delete", because that is what happens — and it is why a mistaken
/// confirmation is still recoverable.
///
/// When the batch includes candidates that cannot be put back
/// ([irreversibleCount] > 0 — an owner command or a privileged system
/// delete), that promise is only partly true, so the title, body and
/// button all switch to mechanism-neutral copy that says plainly which
/// items can be put back and which cannot.
class _CleanConfirmationDialog extends StatelessWidget {
  const _CleanConfirmationDialog({
    required this.count,
    required this.sizeBytes,
    required this.irreversibleCount,
  });

  final int count;
  final int sizeBytes;
  final int irreversibleCount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final mixed = irreversibleCount > 0;

    return AlertDialog(
      backgroundColor: palette.surface,
      title: Text(
        mixed
            ? l10n.cleanConfirmTitleMixed(count)
            : l10n.cleanConfirmTitle(count),
        style: HoopixType.title.copyWith(color: palette.labelPrimary),
      ),
      content: Text(
        mixed
            ? l10n.cleanConfirmBodyMixed(
                formatBytes(sizeBytes),
                irreversibleCount,
              )
            : l10n.cleanConfirmBody(formatBytes(sizeBytes)),
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
          child: Text(
            mixed ? l10n.cleanCleanUp : l10n.cleanMoveToTrash,
            style: HoopixType.body,
          ),
        ),
      ],
    );
  }
}
