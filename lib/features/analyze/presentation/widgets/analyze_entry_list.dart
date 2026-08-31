import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/utils/byte_format.dart';
import 'package:hoopix/core/widgets/ring_gauge.dart';
import 'package:hoopix/core/widgets/tabular_text.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/entry_hint.dart';
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
    required this.onTrash,
    required this.isSelected,
    required this.onToggleSelection,
    required this.hasSelection,
  });

  final List<AnalyzeEntry> entries;
  final int? totalBytes;
  final ValueChanged<AnalyzeEntry> onOpen;
  final ValueChanged<AnalyzeEntry> onReveal;
  final ValueChanged<AnalyzeEntry> onTrash;
  final bool Function(AnalyzeEntry) isSelected;
  final ValueChanged<AnalyzeEntry> onToggleSelection;

  /// Once anything is ticked, every row shows its box — otherwise the boxes
  /// only appear under the pointer.
  final bool hasSelection;

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
          onTrash: () => onTrash(entry),
          isSelected: isSelected(entry),
          onToggleSelection: () => onToggleSelection(entry),
          showSelection: hasSelection,
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
    required this.onTrash,
    required this.isSelected,
    required this.onToggleSelection,
    required this.showSelection,
  });

  final AnalyzeEntry entry;
  final double fraction;
  final VoidCallback onOpen;
  final VoidCallback onReveal;
  final VoidCallback onTrash;
  final bool isSelected;
  final VoidCallback onToggleSelection;
  final bool showSelection;

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
              SizedBox(
                width: 22,
                child: Visibility(
                  visible: widget.showSelection || _isHovered || widget.isSelected,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Checkbox(
                    value: widget.isSelected,
                    onChanged: (_) => widget.onToggleSelection(),
                    activeColor: palette.brand,
                    side: BorderSide(color: palette.labelTertiary),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(width: HoopixSpacing.xs),
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
              _EntryHint(entry: entry),
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
              // Held in the layout at all times so rows don't shift width on
              // hover. Hidden means genuinely gone, not transparent: an
              // invisible button that still takes clicks is a trap, and one
              // whose callback is gated on hover is dead whenever the hover
              // state is stale.
              Visibility(
                visible: _isHovered,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RowAction(
                      icon: Icons.launch,
                      tooltip: l10n.analyzeRevealInFinder,
                      color: palette.labelSecondary,
                      onPressed: widget.onReveal,
                    ),
                    _RowAction(
                      icon: Icons.delete_outline,
                      tooltip: l10n.analyzeMoveToTrash,
                      color: palette.danger,
                      onPressed: widget.onTrash,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One compact icon button in a row's hover actions.
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      color: color,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: EdgeInsets.zero,
    );
  }
}

/// The one-glance signal beside a row: that a directory is regenerable, or
/// that it has gone untouched for a long time. Cleanable wins when both
/// apply, because it is the actionable one — the same precedence as Mole's
/// entry hint.
class _EntryHint extends StatelessWidget {
  const _EntryHint({required this.entry});

  final AnalyzeEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    if (isCleanableDirectory(entry)) {
      return Padding(
        padding: const EdgeInsets.only(left: HoopixSpacing.sm),
        child: Tooltip(
          message: l10n.analyzeCleanableHint,
          child: Icon(
            Icons.cleaning_services_outlined,
            size: 13,
            color: palette.warning,
          ),
        ),
      );
    }

    final unused = unusedForLabel(entry.accessed);
    if (unused == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: HoopixSpacing.sm),
      child: Tooltip(
        message: l10n.analyzeUnusedHint,
        child: Text(
          unused,
          style: HoopixType.caption.copyWith(color: palette.labelTertiary),
        ),
      ),
    );
  }
}
