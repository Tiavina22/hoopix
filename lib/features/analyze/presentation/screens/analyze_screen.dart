import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/core/widgets/metric_card.dart';
import 'package:hoopix/features/analyze/data/repositories/analyze_repository_impl.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';
import 'package:hoopix/features/analyze/domain/repositories/analyze_repository.dart';
import 'package:hoopix/features/analyze/domain/usecases/find_large_files.dart';
import 'package:hoopix/features/analyze/domain/usecases/get_local_snapshot_count.dart';
import 'package:hoopix/features/analyze/domain/usecases/move_to_trash.dart';
import 'package:hoopix/features/analyze/domain/usecases/reveal_in_finder.dart';
import 'package:hoopix/features/analyze/domain/usecases/watch_directory.dart';
import 'package:hoopix/features/analyze/presentation/state/analyze_controller.dart';
import 'package:hoopix/features/analyze/presentation/widgets/analyze_entry_list.dart';
import 'package:hoopix/features/analyze/presentation/widgets/breadcrumb_bar.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// Read-only disk explorer. Opens on the curated overview — where space
/// actually goes on a Mac — and drills into any row from there.
/// [repository] is injectable so tests can substitute a fake.
class AnalyzeScreen extends StatefulWidget {
  const AnalyzeScreen({super.key, this.repository, this.homePath});

  final AnalyzeRepository? repository;
  final String? homePath;

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  late final AnalyzeController _controller;

  @override
  void initState() {
    super.initState();
    final repository = widget.repository ?? AnalyzeRepositoryImpl();
    _controller = AnalyzeController(
      WatchDirectory(repository),
      FindLargeFiles(repository),
      RevealInFinder(repository),
      MoveToTrash(repository),
      GetLocalSnapshotCount(repository),
      homePath:
          widget.homePath ??
          Platform.environment['HOME'] ??
          Directory.systemTemp.path,
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Copies what is currently on screen as JSON, matching the field names
  /// of Mole's `--json` mode.
  Future<void> _copyJson() async {
    final json = _controller.exportJson();
    if (json == null) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: json));
    messenger?.showSnackBar(SnackBar(content: Text(l10n.analyzeCopiedJson)));
  }

  Future<void> _reveal(AnalyzeEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final revealed = await _controller.reveal(entry);
    if (revealed || messenger == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.analyzeRevealFailed(entry.name))),
    );
  }

  /// Nothing is moved until the user confirms it by name and size. The
  /// destination is the Trash, so a mistaken confirmation is still
  /// recoverable — and a protected path is refused natively even here.
  Future<void> _confirmAndTrash(AnalyzeEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _TrashConfirmationDialog(entry: entry),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final refusal = await _controller.moveToTrash(entry);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          refusal == null
              ? l10n.analyzeTrashed(entry.name)
              : l10n.analyzeTrashFailed(entry.name, refusal),
        ),
      ),
    );
  }

  /// The batch version of the same gate: how many rows, how much space, one
  /// confirmation for the lot.
  Future<void> _confirmAndTrashSelected() async {
    final l10n = AppLocalizations.of(context)!;
    final count = _controller.selectedEntries.length;
    final bytes = _controller.selectedBytes;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _TrashConfirmationDialog.batch(
        count: count,
        sizeBytes: bytes,
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final failures = await _controller.moveSelectedToTrash();
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failures.isEmpty
              ? l10n.analyzeTrashedCount(count - failures.length)
              : l10n.analyzeTrashRefusedCount(failures.length),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            HoopixSpacing.xxxl,
            HoopixLayout.trafficLightInset,
            HoopixSpacing.xxxl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(controller: _controller, onCopyJson: _copyJson),
              if (_controller.selected.isNotEmpty) ...[
                const SizedBox(height: HoopixSpacing.md),
                _SelectionBar(
                  controller: _controller,
                  onTrashSelected: _confirmAndTrashSelected,
                ),
              ],
              const SizedBox(height: HoopixSpacing.lg),
              Expanded(
                child: _Body(
                  controller: _controller,
                  onReveal: _reveal,
                  onTrash: _confirmAndTrash,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onCopyJson});

  final AnalyzeController controller;
  final VoidCallback onCopyJson;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final scan = controller.scan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              l10n.sectionAnalyzeLabel,
              style: HoopixType.largeTitle.copyWith(
                color: palette.labelPrimary,
              ),
            ),
            const SizedBox(width: HoopixSpacing.md),
            if (scan != null && scan.entries.isNotEmpty)
              Text(
                _summary(l10n, scan),
                style: HoopixType.callout.copyWith(
                  color: palette.labelTertiary,
                ),
              ),
          ],
        ),
        if (controller.isOverview && (controller.localSnapshotCount ?? 0) > 0) ...[
          const SizedBox(height: HoopixSpacing.xs),
          Text(
            l10n.analyzeLocalSnapshotsNote(controller.localSnapshotCount!),
            style: HoopixType.caption.copyWith(color: palette.labelTertiary),
          ),
        ],
        const SizedBox(height: HoopixSpacing.sm),
        Row(
          children: [
            Expanded(
              child: BreadcrumbBar(
                crumbs: controller.crumbs,
                onTap: controller.open,
              ),
            ),
            const SizedBox(width: HoopixSpacing.md),
            SizedBox(
              width: 180,
              height: 28,
              child: TextField(
                onChanged: controller.setFilter,
                style: HoopixType.callout.copyWith(
                  color: palette.labelPrimary,
                ),
                cursorColor: palette.brand,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.analyzeFilterHint,
                  hintStyle: HoopixType.callout.copyWith(
                    color: palette.labelTertiary,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 14,
                    color: palette.labelTertiary,
                  ),
                  prefixIconConstraints: const BoxConstraints.tightFor(
                    width: 26,
                    height: 26,
                  ),
                  filled: true,
                  fillColor: palette.surfaceSubtle,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: HoopixSpacing.sm,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(HoopixRadius.sm),
                    borderSide: BorderSide(color: palette.separator),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(HoopixRadius.sm),
                    borderSide: BorderSide(color: palette.brand),
                  ),
                ),
              ),
            ),
            const SizedBox(width: HoopixSpacing.md),
            Tooltip(
              message: l10n.analyzeCopyJson,
              child: IconButton(
                onPressed: controller.scan == null ? null : onCopyJson,
                icon: const Icon(Icons.data_object, size: 16),
                color: palette.labelSecondary,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: HoopixSpacing.sm),
            SegmentedButton<AnalyzeView>(
              segments: [
                ButtonSegment(
                  value: AnalyzeView.entries,
                  label: Text(l10n.analyzeViewFolders),
                ),
                ButtonSegment(
                  value: AnalyzeView.largeFiles,
                  label: Text(l10n.analyzeViewLargestFiles),
                ),
              ],
              selected: {controller.view},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  selection.first == AnalyzeView.entries
                  ? controller.showEntries()
                  : controller.showLargeFiles(),
              style: SegmentedButton.styleFrom(
                backgroundColor: palette.surfaceSubtle,
                foregroundColor: palette.labelSecondary,
                selectedBackgroundColor: palette.brandSubtle,
                selectedForegroundColor: palette.brand,
                side: BorderSide(color: palette.separator),
                textStyle: HoopixType.callout,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _summary(AppLocalizations l10n, DirectoryScan scan) {
    // The true count, not how many rows are shown: a directory with 340
    // children lists only its 30 biggest, but the number at the top says
    // 340 — the list is trimmed, not the fact.
    final count = l10n.analyzeItemCount(scan.totalEntryCount);
    final total = scan.totalBytes;
    if (total == null) return count;
    return '$count · ${formatBytes(total)}';
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.onReveal,
    required this.onTrash,
  });

  final AnalyzeController controller;
  final ValueChanged<AnalyzeEntry> onReveal;
  final ValueChanged<AnalyzeEntry> onTrash;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (controller.view == AnalyzeView.largeFiles) {
      return _LargeFilesBody(
        controller: controller,
        onReveal: onReveal,
        onTrash: onTrash,
      );
    }

    final error = controller.error;
    if (error != null) {
      return _Notice(message: l10n.analyzeFailed('$error'), onRetry: controller.retry);
    }

    final scan = controller.scan;
    if (scan == null) return const _Scanning();

    return switch (scan.status) {
      DirectoryScanStatus.permissionDenied => _Notice(
        message: l10n.analyzePermissionDenied,
      ),
      DirectoryScanStatus.failed => _Notice(
        message: l10n.analyzeFailed('${scan.error}'),
        onRetry: controller.retry,
      ),
      _ when scan.entries.isEmpty && !scan.isScanning => _Notice(
        message: l10n.analyzeEmptyDirectory,
      ),
      _ when controller.visibleEntries.isEmpty && !scan.isScanning => _Notice(
        message: l10n.analyzeNoMatches,
      ),
      _ => _EntriesList(controller: controller, onReveal: onReveal, onTrash: onTrash),
    };
  }
}

/// The capped listing, plus — only while unfiltered, so it can't be misread
/// as a filter result — a note when the directory holds more than the 30
/// shown.
class _EntriesList extends StatelessWidget {
  const _EntriesList({
    required this.controller,
    required this.onReveal,
    required this.onTrash,
  });

  final AnalyzeController controller;
  final ValueChanged<AnalyzeEntry> onReveal;
  final ValueChanged<AnalyzeEntry> onTrash;

  @override
  Widget build(BuildContext context) {
    final scan = controller.scan!;
    final truncated =
        controller.filter.isEmpty && scan.totalEntryCount > scan.entries.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AnalyzeEntryList(
            entries: controller.visibleEntries,
            totalBytes: scan.totalBytes,
            onOpen: controller.openChild,
            onReveal: onReveal,
            onTrash: onTrash,
            isSelected: controller.isSelected,
            onToggleSelection: controller.toggleSelection,
            hasSelection: controller.selected.isNotEmpty,
          ),
        ),
        if (truncated) _TruncationNote(shown: scan.entries.length, total: scan.totalEntryCount),
      ],
    );
  }
}

class _TruncationNote extends StatelessWidget {
  const _TruncationNote({required this.shown, required this.total});

  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HoopixSpacing.sm),
      child: Text(
        l10n.analyzeShowingLargest(shown, total),
        style: HoopixType.caption.copyWith(color: palette.labelTertiary),
      ),
    );
  }
}

/// The largest files under the open directory, answered by Spotlight. Files
/// only — there is nothing to drill into, so rows are not tappable.
class _LargeFilesBody extends StatelessWidget {
  const _LargeFilesBody({
    required this.controller,
    required this.onReveal,
    required this.onTrash,
  });

  final AnalyzeController controller;
  final ValueChanged<AnalyzeEntry> onReveal;
  final ValueChanged<AnalyzeEntry> onTrash;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (controller.isLoadingLargeFiles) return const _Scanning();

    final error = controller.largeFilesError;
    if (error != null) {
      return _Notice(
        message: l10n.analyzeFailed('$error'),
        onRetry: controller.showLargeFiles,
      );
    }

    final found = controller.largeFiles ?? const [];
    if (found.isEmpty) {
      return _Notice(message: l10n.analyzeNoLargeFiles);
    }

    final files = controller.visibleEntries;
    if (files.isEmpty) return _Notice(message: l10n.analyzeNoMatches);

    return AnalyzeEntryList(
      entries: files,
      // Each row is measured against the biggest file rather than a folder
      // total, so the bars compare the files to each other.
      totalBytes: files.first.sizeBytes,
      onOpen: (_) {},
      onReveal: onReveal,
      onTrash: onTrash,
      isSelected: controller.isSelected,
      onToggleSelection: controller.toggleSelection,
      hasSelection: controller.selected.isNotEmpty,
    );
  }
}

/// Names what is about to move and how big it is, and says where it goes.
/// "Move to Trash" rather than "Delete", because that is what happens.
class _TrashConfirmationDialog extends StatelessWidget {
  const _TrashConfirmationDialog({required AnalyzeEntry this.entry})
    : count = 1,
      sizeBytes = null;

  const _TrashConfirmationDialog.batch({
    required this.count,
    required int this.sizeBytes,
  }) : entry = null;

  final AnalyzeEntry? entry;
  final int count;
  final int? sizeBytes;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final entry = this.entry;
    final size = entry?.sizeBytes ?? sizeBytes;

    return AlertDialog(
      backgroundColor: palette.surface,
      title: Text(
        entry != null
            ? l10n.analyzeTrashTitle(entry.name)
            : l10n.analyzeTrashTitleCount(count),
        style: HoopixType.title.copyWith(color: palette.labelPrimary),
      ),
      content: Text(
        size == null || size == 0
            ? l10n.analyzeTrashBody
            : l10n.analyzeTrashBodyWithSize(formatBytes(size)),
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
          child: Text(l10n.analyzeMoveToTrash, style: HoopixType.body),
        ),
      ],
    );
  }
}

class _Scanning extends StatelessWidget {
  const _Scanning();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: palette.brand,
            ),
          ),
          const SizedBox(height: HoopixSpacing.lg),
          Text(
            l10n.analyzeScanning,
            style: HoopixType.body.copyWith(color: palette.labelSecondary),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UnavailableNote(label: message),
          if (onRetry != null) ...[
            const SizedBox(height: HoopixSpacing.lg),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: palette.brand),
              child: Text(l10n.analyzeRetry, style: HoopixType.body),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown only while rows are ticked: what is selected, and the one action
/// that applies to all of them.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.controller, required this.onTrashSelected});

  final AnalyzeController controller;
  final VoidCallback onTrashSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final bytes = controller.selectedBytes;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HoopixSpacing.md,
        vertical: HoopixSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: palette.brandSubtle,
        borderRadius: BorderRadius.circular(HoopixRadius.sm + 2),
        border: Border.all(color: palette.separator),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              bytes == 0
                  ? l10n.analyzeSelectedCount(controller.selected.length)
                  : '${l10n.analyzeSelectedCount(controller.selected.length)}'
                        ' · ${formatBytes(bytes)}',
              style: HoopixType.callout.copyWith(color: palette.labelPrimary),
            ),
          ),
          TextButton(
            onPressed: controller.clearSelection,
            style: TextButton.styleFrom(foregroundColor: palette.labelSecondary),
            child: Text(l10n.analyzeClearSelection, style: HoopixType.callout),
          ),
          TextButton(
            onPressed: onTrashSelected,
            style: TextButton.styleFrom(foregroundColor: palette.danger),
            child: Text(l10n.analyzeMoveToTrash, style: HoopixType.callout),
          ),
        ],
      ),
    );
  }
}
