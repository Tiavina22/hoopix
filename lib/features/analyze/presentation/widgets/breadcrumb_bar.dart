import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/features/analyze/data/datasources/directory_local_datasource.dart';
import 'package:hoopix/features/analyze/presentation/state/analyze_controller.dart';
import 'package:hoopix/features/analyze/presentation/widgets/overview_label.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// The trail from the overview down to the open directory. Scrolls sideways
/// rather than wrapping, so a deep path never pushes the listing down.
class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({
    super.key,
    required this.crumbs,
    required this.onTap,
  });

  final List<AnalyzeCrumb> crumbs;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (index, crumb) in crumbs.indexed) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HoopixSpacing.xs,
                ),
                child: Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: palette.labelTertiary,
                ),
              ),
            _Segment(
              label: crumb.isOverview
                  ? l10n.analyzeOverviewBreadcrumb
                  : overviewLabel(
                      l10n,
                      crumb.kind,
                      crumb.label ?? basename(crumb.path),
                    ),
              isCurrent: index == crumbs.length - 1,
              onTap: () => onTap(crumb.path),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.isCurrent,
    required this.onTap,
  });

  final String label;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return MouseRegion(
      cursor: widget.isCurrent
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.isCurrent ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(
            horizontal: HoopixSpacing.sm,
            vertical: HoopixSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: !widget.isCurrent && _isHovered
                ? palette.separator
                : Colors.transparent,
            borderRadius: BorderRadius.circular(HoopixRadius.sm),
          ),
          child: Text(
            widget.label,
            style: HoopixType.callout.copyWith(
              color: widget.isCurrent
                  ? palette.labelPrimary
                  : palette.labelSecondary,
              fontWeight: widget.isCurrent ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
