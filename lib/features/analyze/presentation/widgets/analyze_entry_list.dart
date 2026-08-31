import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/core/widgets/ring_gauge.dart';
import 'package:hoopix/core/widgets/tabular_text.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/presentation/widgets/overview_label.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// The directory listing. A `ListView.builder` rather than a card of rows
/// because a single folder can hold hundreds of entries (`~/Library` alone
/// has 74), which needs virtualization to stay smooth.
class AnalyzeEntryList extends StatelessWidget {
  const AnalyzeEntryList({
    super.key,
    required this.entries,
    required this.totalBytes,
    required this.onOpen,
    required this.onReveal,
  });

  final List<AnalyzeEntry> entries;
  final int? totalBytes;
  final ValueChanged<AnalyzeEntry> onOpen;
  final ValueChanged<AnalyzeEntry> onReveal;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: HoopixSpacing.xxxl),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _AnalyzeEntryRow(
          entry: entry,
          fraction: entry.fractionOf(totalBytes),
          onOpen: () => onOpen(entry),
          onReveal: () => onReveal(entry),
        );
      },
    );
  }
}

class _AnalyzeEntryRow extends StatefulWidget {
  const _AnalyzeEntryRow({
    required this.entry,
    required this.fraction,
    required this.onOpen,
    required this.onReveal,
  });

  final AnalyzeEntry entry;
  final double fraction;
  final VoidCallback onOpen;
  final VoidCallback onReveal;

  @override
  State<_AnalyzeEntryRow> createState() => _AnalyzeEntryRowState();
}

class _AnalyzeEntryRowState extends State<_AnalyzeEntryRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final entry = widget.entry;
    final size = entry.sizeBytes;

    return MouseRegion(
      cursor: entry.isDirectory
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: entry.isDirectory ? widget.onOpen : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(
            horizontal: HoopixSpacing.md,
            vertical: HoopixSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? palette.surfaceSubtle : Colors.transparent,
            borderRadius: BorderRadius.circular(HoopixRadius.sm + 2),
          ),
          child: Row(
            children: [
              Icon(
                entry.isDirectory
                    ? Icons.folder_outlined
                    : Icons.insert_drive_file_outlined,
                size: 16,
                color: entry.isDirectory
                    ? palette.brand
                    : palette.labelTertiary,
              ),
              const SizedBox(width: HoopixSpacing.md),
              Expanded(
                child: Text(
                  overviewLabel(l10n, entry.overviewKind, entry.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HoopixType.body.copyWith(color: palette.labelPrimary),
                ),
              ),
              const SizedBox(width: HoopixSpacing.md),
              SizedBox(
                width: 96,
                child: LinearMeter(value: widget.fraction, height: 4),
              ),
              const SizedBox(width: HoopixSpacing.md),
              SizedBox(
                width: 84,
                // Fixed width keeps the size column aligned down the list;
                // scaleDown keeps an unusually long value ("999.9 GB" at a
                // large text scale) from overflowing the row instead.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: size == null
                      ? Text(
                          l10n.analyzeEntryUnknownSize,
                          style: HoopixType.numeric.copyWith(
                            color: palette.labelTertiary,
                          ),
                        )
                      : TabularText(
                          formatBytes(size),
                          style: HoopixType.numeric.copyWith(
                            color: palette.labelPrimary,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: HoopixSpacing.sm),
              // Kept in the layout at all times so rows don't shift width on
              // hover; only its visibility changes.
              Opacity(
                opacity: _isHovered ? 1 : 0,
                child: IconButton(
                  onPressed: _isHovered ? widget.onReveal : null,
                  icon: const Icon(Icons.launch, size: 14),
                  color: palette.labelSecondary,
                  tooltip: l10n.analyzeRevealInFinder,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
