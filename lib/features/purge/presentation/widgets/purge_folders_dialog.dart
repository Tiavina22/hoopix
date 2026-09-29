import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/features/purge/domain/entities/purge_search_roots.dart';
import 'package:hoopix/features/purge/domain/usecases/load_purge_roots.dart';
import 'package:hoopix/features/purge/domain/usecases/save_purge_roots.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// Chooses the folders Purge scans — the GUI counterpart of
/// `mo purge --paths`. Pops `true` once a new list is saved.
class PurgeFoldersDialog extends StatefulWidget {
  const PurgeFoldersDialog({
    super.key,
    required this.load,
    required this.save,
    required this.displayPath,
    required this.folderExists,
  });

  final LoadPurgeRoots load;
  final SavePurgeRoots save;
  final String displayPath;
  final bool Function(String path) folderExists;

  @override
  State<PurgeFoldersDialog> createState() => _PurgeFoldersDialogState();
}

class _PurgeFoldersDialogState extends State<PurgeFoldersDialog> {
  final _field = TextEditingController();

  PurgeRootsSelection? _selection;
  Object? _loadError;
  String? _refusal;
  Object? _saveError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.load().then(
      (selection) {
        if (mounted) setState(() => _selection = selection);
      },
      onError: (Object error) {
        if (mounted) setState(() => _loadError = error);
      },
    );
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _add() {
    final selection = _selection;
    if (selection == null) return;
    final result = selection.withRoot(_field.text);
    setState(() {
      _selection = result.selection;
      _refusal = result.refusal;
      if (result.refusal == null) _field.clear();
    });
  }

  Future<void> _save() async {
    final selection = _selection;
    if (selection == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.save(selection);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final selection = _selection;

    return AlertDialog(
      backgroundColor: palette.surface,
      title: Text(
        l10n.purgeFoldersTitle,
        style: HoopixType.title.copyWith(color: palette.labelPrimary),
      ),
      content: SizedBox(
        width: 520,
        height: 420,
        child: _loadError != null
            ? Text(
                l10n.purgeFoldersLoadFailed('$_loadError'),
                style: HoopixType.body.copyWith(color: palette.danger),
              )
            : selection == null
            ? const Center(child: CircularProgressIndicator())
            : _Editor(
                selection: selection,
                displayPath: widget.displayPath,
                folderExists: widget.folderExists,
                field: _field,
                refusal: _refusal,
                saveError: _saveError,
                onAdd: _add,
                onRemove: (root) =>
                    setState(() => _selection = selection.withoutRoot(root)),
                onAutomatic: () =>
                    setState(() => _selection = selection.automatic()),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: palette.labelSecondary),
          child: Text(l10n.analyzeCancel, style: HoopixType.body),
        ),
        TextButton(
          onPressed: selection == null || _saving ? null : _save,
          style: TextButton.styleFrom(foregroundColor: palette.brand),
          child: Text(l10n.purgeFoldersSave, style: HoopixType.body),
        ),
      ],
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.selection,
    required this.displayPath,
    required this.folderExists,
    required this.field,
    required this.refusal,
    required this.saveError,
    required this.onAdd,
    required this.onRemove,
    required this.onAutomatic,
  });

  final PurgeRootsSelection selection;
  final String displayPath;
  final bool Function(String path) folderExists;
  final TextEditingController field;
  final String? refusal;
  final Object? saveError;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final VoidCallback onAutomatic;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final refusal = this.refusal;
    final home = selection.home;

    return ListView(
      children: [
        Text(
          l10n.purgeFoldersSubtitle(displayPath),
          style: HoopixType.callout.copyWith(color: palette.labelSecondary),
        ),
        const SizedBox(height: HoopixSpacing.xs),
        Text(
          selection.isAutomatic
              ? l10n.purgeFoldersAutomatic
              : l10n.purgeFoldersCustom,
          style: HoopixType.callout.copyWith(color: palette.labelTertiary),
        ),
        if (saveError != null) ...[
          const SizedBox(height: HoopixSpacing.sm),
          Text(
            l10n.purgeFoldersSaveFailed('$saveError'),
            style: HoopixType.callout.copyWith(color: palette.danger),
          ),
        ],
        const SizedBox(height: HoopixSpacing.md),
        if (selection.roots.isEmpty)
          Text(
            l10n.purgeFoldersNone,
            style: HoopixType.body.copyWith(color: palette.labelTertiary),
          ),
        for (final root in selection.roots)
          Row(
            children: [
              Expanded(
                child: Text(
                  root == home || root.startsWith('$home/')
                      ? '~${root.substring(home.length)}'
                      : root,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HoopixType.body.copyWith(color: palette.labelPrimary),
                ),
              ),
              if (!folderExists(root))
                Text(
                  l10n.purgeFoldersNotFound,
                  style: HoopixType.caption.copyWith(
                    color: palette.labelTertiary,
                  ),
                ),
              IconButton(
                tooltip: l10n.purgeFoldersRemove,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.remove_circle_outline,
                  size: 18,
                  color: palette.labelSecondary,
                ),
                onPressed: () => onRemove(root),
              ),
            ],
          ),
        const SizedBox(height: HoopixSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: field,
                style: HoopixType.body.copyWith(color: palette.labelPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.purgeFoldersHint,
                  errorText: refusal == null
                      ? null
                      : _refusalLabel(l10n, refusal),
                ),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: HoopixSpacing.sm),
            TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(foregroundColor: palette.brand),
              child: Text(l10n.purgeFoldersAdd, style: HoopixType.body),
            ),
          ],
        ),
        if (!selection.isAutomatic) ...[
          const SizedBox(height: HoopixSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onAutomatic,
              style: TextButton.styleFrom(
                foregroundColor: palette.labelSecondary,
              ),
              child: Text(
                l10n.purgeFoldersUseAutomatic,
                style: HoopixType.body,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _refusalLabel(AppLocalizations l10n, String reason) =>
      switch (reason) {
        'Must be absolute path' => l10n.purgeFoldersRefusedNotAbsolute,
        'Path traversal not allowed' => l10n.purgeFoldersRefusedTraversal,
        'Whole disk not allowed' => l10n.purgeFoldersRefusedWholeDisk,
        _ => reason,
      };
}
