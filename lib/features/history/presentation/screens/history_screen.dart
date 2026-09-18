import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/core/theme/hoopix_colors.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/features/history/data/repositories/history_repository_impl.dart';
import 'package:hoopix/features/history/domain/entities/day_group.dart';
import 'package:hoopix/features/history/domain/entities/operation_history_entry.dart';
import 'package:hoopix/features/history/domain/repositories/history_repository.dart';
import 'package:hoopix/features/history/domain/usecases/fetch_operation_history.dart';
import 'package:hoopix/features/history/presentation/state/history_controller.dart';
import 'package:hoopix/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// What hoopix has already decided about a path, read from
/// `~/Library/Logs/hoopix/operations.log` — the record [OperationLog] keeps
/// of every Clean and Uninstall decision. Read-only: nothing here can be
/// retried or undone from this screen, and loading it never touches the log.
///
/// This is the screen that would have told a CapCut-refusal story plainly:
/// the log always carried the reason a move was refused, but nothing in the
/// app showed it until now.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.repository, this.homePath});

  final HistoryRepository? repository;
  final String? homePath;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final HistoryController _controller;

  @override
  void initState() {
    super.initState();
    final home =
        widget.homePath ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final repository = widget.repository ?? HistoryRepositoryImpl(home: home);
    _controller = HistoryController(FetchOperationHistory(repository))..load();
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

  final HistoryController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          l10n.sectionHistoryLabel,
          style: HoopixType.largeTitle.copyWith(color: palette.labelPrimary),
        ),
        const Spacer(),
        IconButton(
          tooltip: l10n.historyRefresh,
          onPressed: controller.isLoading ? null : controller.refresh,
          icon: Icon(Icons.refresh, color: palette.labelSecondary),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final HistoryController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    final error = controller.error;
    if (error != null) {
      return _Notice(message: l10n.historyFailed('$error'));
    }

    final entries = controller.entries;
    if (entries == null) {
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

    if (entries.isEmpty) {
      return _Notice(message: l10n.historyEmpty);
    }

    final groups = groupHistoryByDay(entries);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: HoopixSpacing.xxxl),
      itemCount: groups.length,
      itemBuilder: (context, index) => _DaySection(group: groups[index]),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.group});

  final DayGroup group;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.only(bottom: HoopixSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dayLabel(group.day, l10n),
            style: HoopixType.callout.copyWith(
              color: palette.labelTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: HoopixSpacing.sm),
          for (final entry in group.entries) ...[
            _EntryRow(entry: entry),
            const SizedBox(height: HoopixSpacing.xs),
          ],
        ],
      ),
    );
  }

  String _dayLabel(DateTime day, AppLocalizations l10n) {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    if (day == todayMidnight) return l10n.historyToday;
    if (day == todayMidnight.subtract(const Duration(days: 1))) {
      return l10n.historyYesterday;
    }
    return DateFormat.yMMMMd(l10n.localeName).format(day);
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final OperationHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final outcome = _outcomeStyle(entry.outcome, palette, l10n);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(HoopixRadius.md),
        border: Border.all(color: palette.separator),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HoopixSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(outcome.icon, size: 16, color: outcome.color),
            const SizedBox(width: HoopixSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.path,
                          overflow: TextOverflow.ellipsis,
                          style: HoopixType.body.copyWith(
                            color: palette.labelPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: HoopixSpacing.sm),
                      Text(
                        DateFormat.jm(l10n.localeName).format(entry.at),
                        style: HoopixType.caption.copyWith(
                          color: palette.labelTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: HoopixSpacing.xs),
                  Wrap(
                    spacing: HoopixSpacing.sm,
                    runSpacing: HoopixSpacing.xs,
                    children: [
                      _Badge(text: entry.command, color: palette.labelTertiary),
                      _Badge(text: outcome.label, color: outcome.color),
                      if (entry.sizeBytes != null)
                        Text(
                          formatBytes(entry.sizeBytes!),
                          style: HoopixType.caption.copyWith(
                            color: palette.labelTertiary,
                          ),
                        ),
                    ],
                  ),
                  if (entry.detail != null) ...[
                    const SizedBox(height: HoopixSpacing.xs),
                    Text(
                      entry.detail!,
                      style: HoopixType.caption.copyWith(
                        color: palette.labelSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeStyle {
  const _OutcomeStyle({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;
}

_OutcomeStyle _outcomeStyle(
  OperationOutcome outcome,
  HoopixPalette palette,
  AppLocalizations l10n,
) => switch (outcome) {
  OperationOutcome.trashed => _OutcomeStyle(
    icon: Icons.check_circle_outline,
    color: palette.success,
    label: l10n.historyOutcomeTrashed,
  ),
  OperationOutcome.refused => _OutcomeStyle(
    icon: Icons.error_outline,
    color: palette.danger,
    label: l10n.historyOutcomeRefused,
  ),
  OperationOutcome.skipped => _OutcomeStyle(
    icon: Icons.pause_circle_outline,
    color: palette.warning,
    label: l10n.historyOutcomeSkipped,
  ),
  OperationOutcome.cleared => _OutcomeStyle(
    icon: Icons.auto_awesome_outlined,
    color: palette.brand,
    label: l10n.historyOutcomeCleared,
  ),
};

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
