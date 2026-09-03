import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/features/optimize/data/repositories/optimize_repository_impl.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';
import 'package:hoopix/features/optimize/domain/repositories/optimize_repository.dart';
import 'package:hoopix/features/optimize/domain/usecases/run_optimize.dart';
import 'package:hoopix/features/optimize/presentation/state/optimize_controller.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// The maintenance task list and its one action: run everything in it.
/// There is nothing here to select — every task is Mole's own
/// `SAFE_VALUES=true` — so the catalog shown before running is the whole
/// preview, the same way [OptimizeController]'s docs describe it.
class OptimizeScreen extends StatefulWidget {
  const OptimizeScreen({super.key, this.repository, this.homePath});

  final OptimizeRepository? repository;
  final String? homePath;

  @override
  State<OptimizeScreen> createState() => _OptimizeScreenState();
}

class _OptimizeScreenState extends State<OptimizeScreen> {
  late final OptimizeController _controller;

  @override
  void initState() {
    super.initState();
    final home =
        widget.homePath ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final repository = widget.repository ?? OptimizeRepositoryImpl(home: home);
    _controller = OptimizeController(RunOptimize(repository));
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
            Expanded(child: _TaskList(controller: _controller)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final OptimizeController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              l10n.sectionOptimizeLabel,
              style: HoopixType.largeTitle.copyWith(
                color: palette.labelPrimary,
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: controller.isRunning ? null : controller.run,
              style: FilledButton.styleFrom(
                backgroundColor: palette.brand,
                disabledBackgroundColor: palette.surfaceSubtle,
                foregroundColor: Colors.white,
                disabledForegroundColor: palette.labelTertiary,
                textStyle: HoopixType.body,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                controller.isRunning
                    ? l10n.optimizeRunning
                    : l10n.optimizeRunButton,
              ),
            ),
          ],
        ),
        const SizedBox(height: HoopixSpacing.xs),
        Text(
          l10n.optimizeIdleHint,
          style: HoopixType.callout.copyWith(color: palette.labelSecondary),
        ),
      ],
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.controller});

  final OptimizeController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final error = controller.error;
    if (error != null) {
      return _Notice(message: l10n.optimizeFailed('$error'));
    }

    final catalog = controller.catalog;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: HoopixSpacing.xxxl),
      itemCount: catalog.length,
      separatorBuilder: (_, _) => const SizedBox(height: HoopixSpacing.sm),
      itemBuilder: (context, index) {
        final task = catalog[index];
        return _TaskRow(
          task: task,
          result: controller.results[task.action],
          isRunning: controller.isRunning,
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.result,
    required this.isRunning,
  });

  final OptimizeTask task;
  final OptimizeTaskResult? result;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HoopixSpacing.lg,
        vertical: HoopixSpacing.md,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceSubtle,
        borderRadius: BorderRadius.circular(HoopixRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: HoopixType.body.copyWith(
                    color: palette.labelPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  task.description,
                  style: HoopixType.callout.copyWith(
                    color: palette.labelSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: HoopixSpacing.md),
          _StatusBadge(result: result, isRunning: isRunning),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.result, required this.isRunning});

  final OptimizeTaskResult? result;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (result == null) {
      if (!isRunning) return const SizedBox.shrink();
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: palette.labelTertiary,
        ),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    final (label, color) = switch (result!.outcome) {
      OptimizeOutcome.applied => (l10n.optimizeOutcomeApplied, palette.success),
      OptimizeOutcome.unchanged => (
        l10n.optimizeOutcomeUnchanged,
        palette.labelTertiary,
      ),
      OptimizeOutcome.skipped => (
        l10n.optimizeOutcomeSkipped,
        palette.labelTertiary,
      ),
      OptimizeOutcome.unavailable => (
        l10n.optimizeOutcomeUnavailable,
        palette.labelTertiary,
      ),
      OptimizeOutcome.attention => (
        l10n.optimizeOutcomeAttention,
        palette.warning,
      ),
      OptimizeOutcome.failed => (l10n.optimizeOutcomeFailed, palette.danger),
    };

    return Text(
      label,
      style: HoopixType.callout.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
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
