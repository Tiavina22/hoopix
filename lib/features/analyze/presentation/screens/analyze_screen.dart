import 'dart:io';

import 'package:flutter/material.dart';
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

  Future<void> _reveal(AnalyzeEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final revealed = await _controller.reveal(entry);
    if (revealed || messenger == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.analyzeRevealFailed(entry.name))),
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
              _Header(controller: _controller),
              const SizedBox(height: HoopixSpacing.lg),
              Expanded(child: _Body(controller: _controller, onReveal: _reveal)),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final AnalyzeController controller;

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
    final count = l10n.analyzeItemCount(scan.entries.length);
    final total = scan.totalBytes;
    if (total == null) return count;
    return '$count · ${formatBytes(total)}';
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.onReveal});

  final AnalyzeController controller;
  final ValueChanged<AnalyzeEntry> onReveal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (controller.view == AnalyzeView.largeFiles) {
      return _LargeFilesBody(controller: controller, onReveal: onReveal);
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
      _ => AnalyzeEntryList(
        entries: scan.entries,
        totalBytes: scan.totalBytes,
        onOpen: controller.openChild,
        onReveal: onReveal,
      ),
    };
  }
}

/// The largest files under the open directory, answered by Spotlight. Files
/// only — there is nothing to drill into, so rows are not tappable.
class _LargeFilesBody extends StatelessWidget {
  const _LargeFilesBody({required this.controller, required this.onReveal});

  final AnalyzeController controller;
  final ValueChanged<AnalyzeEntry> onReveal;

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

    final files = controller.largeFiles ?? const [];
    if (files.isEmpty) {
      return _Notice(message: l10n.analyzeNoLargeFiles);
    }

    return AnalyzeEntryList(
      entries: files,
      // Each row is measured against the biggest file rather than a folder
      // total, so the bars compare the files to each other.
      totalBytes: files.first.sizeBytes,
      onOpen: (_) {},
      onReveal: onReveal,
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
