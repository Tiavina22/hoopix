import 'package:flutter/material.dart';
import 'package:hoopix/core/brand/hoopix_logo.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/features/about/domain/entities/contributor.dart';
import 'package:hoopix/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

const _creatorProfileUrl = 'https://github.com/Tiavina22';
const _licenseUrl = 'https://github.com/Tiavina22/hoopix/blob/main/LICENSE';

/// hoopix's own About panel, styled with the same `AlertDialog` +
/// `HoopixType`/`context.palette` tokens every other dialog in the app
/// uses (`_UninstallConfirmationDialog`, `_LeftBehindDialog`). Reachable
/// from Settings and from the native "About hoopix" app-menu item
/// (`HoopixApp`'s `fit.hoopix/about` channel listener).
///
/// [fetchVersion] and [openUrl] are injectable so a widget test never
/// touches a real platform channel or opens a real browser — the same
/// seam every process/network integration in this codebase already uses.
class HoopixAboutDialog extends StatelessWidget {
  const HoopixAboutDialog({super.key, this.fetchVersion, this.openUrl});

  final Future<String> Function()? fetchVersion;
  final Future<void> Function(Uri url)? openUrl;

  Future<String> _version() =>
      fetchVersion?.call() ??
      PackageInfo.fromPlatform().then((info) => info.version);

  Future<void> _open(Uri url) =>
      openUrl?.call(url) ??
      launcher.launchUrl(url, mode: launcher.LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      backgroundColor: palette.surface,
      contentPadding: const EdgeInsets.fromLTRB(
        HoopixSpacing.xxl,
        HoopixSpacing.xxl,
        HoopixSpacing.xxl,
        HoopixSpacing.lg,
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HoopixLogo(
              size: 56,
              gradient: LinearGradient(
                colors: [palette.brand, palette.brandStrong],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            const SizedBox(height: HoopixSpacing.md),
            Text(
              'Hoopix',
              style: HoopixType.title.copyWith(color: palette.labelPrimary),
            ),
            const SizedBox(height: HoopixSpacing.xs),
            Text(
              l10n.aboutTagline,
              textAlign: TextAlign.center,
              style: HoopixType.callout.copyWith(color: palette.labelSecondary),
            ),
            const SizedBox(height: HoopixSpacing.sm),
            FutureBuilder<String>(
              future: _version(),
              builder: (context, snapshot) {
                final version = snapshot.data;
                if (version == null) return const SizedBox(height: 16);
                return Text(
                  l10n.aboutVersion(version),
                  style: HoopixType.caption.copyWith(
                    color: palette.labelTertiary,
                  ),
                );
              },
            ),
            const SizedBox(height: HoopixSpacing.xl),
            Divider(color: palette.separator, height: 1),
            const SizedBox(height: HoopixSpacing.lg),
            _CreditRow(
              avatarAsset: 'assets/creators/tiavina.png',
              label: l10n.aboutCreatedBy('Tiavina'),
              onTap: () => _open(Uri.parse(_creatorProfileUrl)),
            ),
            const SizedBox(height: HoopixSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.aboutContributorsTitle,
                style: HoopixType.callout.copyWith(
                  color: palette.labelTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: HoopixSpacing.sm),
            Wrap(
              alignment: WrapAlignment.start,
              spacing: HoopixSpacing.lg,
              runSpacing: HoopixSpacing.sm,
              children: [
                for (final contributor in hoopixContributors)
                  _ContributorAvatar(
                    contributor: contributor,
                    onTap: () => _open(Uri.parse(contributor.profileUrl)),
                  ),
              ],
            ),
            const SizedBox(height: HoopixSpacing.lg),
            Divider(color: palette.separator, height: 1),
            const SizedBox(height: HoopixSpacing.lg),
            _LinkText(
              text: l10n.aboutLicense,
              onTap: () => _open(Uri.parse(_licenseUrl)),
            ),
            const SizedBox(height: HoopixSpacing.xs),
            Text(
              '© ${DateTime.now().year} Tiavina Ramilison',
              style: HoopixType.caption.copyWith(color: palette.labelTertiary),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: palette.brand),
          child: Text(l10n.aboutClose, style: HoopixType.body),
        ),
      ],
    );
  }
}

/// The creator's circular avatar plus a name label to its right — one row,
/// wider than a bare [_ContributorAvatar].
class _CreditRow extends StatelessWidget {
  const _CreditRow({
    required this.avatarAsset,
    required this.label,
    required this.onTap,
  });

  final String avatarAsset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Avatar(assetPath: avatarAsset, size: 40),
            const SizedBox(width: HoopixSpacing.sm),
            Text(
              label,
              style: HoopixType.body.copyWith(color: palette.labelPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// One contributor: avatar above their name, both tappable, stacked so a
/// future longer list wraps cleanly.
class _ContributorAvatar extends StatelessWidget {
  const _ContributorAvatar({required this.contributor, required this.onTap});

  final Contributor contributor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Avatar(assetPath: contributor.avatarAsset, size: 40),
            const SizedBox(height: HoopixSpacing.xs),
            Text(
              contributor.name,
              style: HoopixType.caption.copyWith(color: palette.labelSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.assetPath, required this.size});

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ClipOval(
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Container(width: size, height: size, color: palette.surfaceSubtle),
      ),
    );
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          text,
          style: HoopixType.callout.copyWith(
            color: palette.brand,
            decoration: TextDecoration.underline,
            decorationColor: palette.brand,
          ),
        ),
      ),
    );
  }
}
