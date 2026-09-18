import 'package:flutter/material.dart';
import 'package:hoopix/core/platform/app_version.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// The "Open source · v1.2.3" line at the foot of the sidebar, with the real
/// running version. It used to be a hand-typed `'0.1.0'`, which went stale
/// the moment `pubspec.yaml` changed.
///
/// Shows nothing until the version is known, and nothing if it cannot be
/// read: a footer without a number is better than one with a wrong number.
/// [fetchVersion] is injectable so a test never touches a platform channel.
class SidebarFooter extends StatefulWidget {
  const SidebarFooter({super.key, this.fetchVersion});

  final Future<String> Function()? fetchVersion;

  @override
  State<SidebarFooter> createState() => _SidebarFooterState();
}

class _SidebarFooterState extends State<SidebarFooter> {
  late final Future<String> _version;

  @override
  void initState() {
    super.initState();
    _version = (widget.fetchVersion ?? readAppVersion)();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HoopixSpacing.lg,
        HoopixSpacing.md,
        HoopixSpacing.lg,
        HoopixSpacing.lg,
      ),
      child: FutureBuilder<String>(
        future: _version,
        builder: (context, snapshot) {
          final version = snapshot.data;
          if (version == null) return const SizedBox.shrink();
          return Text(
            l10n.openSourceFooter(version),
            style: HoopixType.caption.copyWith(color: palette.labelTertiary),
          );
        },
      ),
    );
  }
}
