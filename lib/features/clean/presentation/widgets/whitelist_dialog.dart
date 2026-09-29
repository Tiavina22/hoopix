import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/features/clean/domain/entities/whitelist_catalog.dart';
import 'package:hoopix/features/clean/domain/entities/whitelist_selection.dart';
import 'package:hoopix/features/clean/domain/usecases/load_whitelist.dart';
import 'package:hoopix/features/clean/domain/usecases/save_whitelist.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// Chooses which caches Clean must leave alone — the GUI counterpart of
/// `mo clean --whitelist`. Pops `true` once a new whitelist is saved.
class WhitelistDialog extends StatefulWidget {
  const WhitelistDialog({
    super.key,
    required this.load,
    required this.save,
    required this.displayPath,
  });

  final LoadWhitelist load;
  final SaveWhitelist save;
  final String displayPath;

  @override
  State<WhitelistDialog> createState() => _WhitelistDialogState();
}

class _WhitelistDialogState extends State<WhitelistDialog> {
  final _customField = TextEditingController();

  WhitelistSelection? _selection;
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
    _customField.dispose();
    super.dispose();
  }

  void _addCustom() {
    final selection = _selection;
    if (selection == null) return;
    final result = selection.withCustom(_customField.text);
    setState(() {
      _selection = result.selection;
      _refusal = result.refusal;
      if (result.refusal == null) _customField.clear();
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
        l10n.whitelistTitle,
        style: HoopixType.title.copyWith(color: palette.labelPrimary),
      ),
      content: SizedBox(
        width: 560,
        height: 520,
        child: _loadError != null
            ? Text(
                l10n.whitelistLoadFailed('$_loadError'),
                style: HoopixType.body.copyWith(color: palette.danger),
              )
            : selection == null
            ? const Center(child: CircularProgressIndicator())
            : _Editor(
                selection: selection,
                displayPath: widget.displayPath,
                customField: _customField,
                refusal: _refusal,
                saveError: _saveError,
                onToggle: (item) =>
                    setState(() => _selection = selection.toggled(item)),
                onAddCustom: _addCustom,
                onRemoveCustom: (line) =>
                    setState(() => _selection = selection.withoutCustom(line)),
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
          child: Text(l10n.whitelistSave, style: HoopixType.body),
        ),
      ],
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.selection,
    required this.displayPath,
    required this.customField,
    required this.refusal,
    required this.saveError,
    required this.onToggle,
    required this.onAddCustom,
    required this.onRemoveCustom,
  });

  final WhitelistSelection selection;
  final String displayPath;
  final TextEditingController customField;
  final String? refusal;
  final Object? saveError;
  final ValueChanged<WhitelistCatalogItem> onToggle;
  final VoidCallback onAddCustom;
  final ValueChanged<String> onRemoveCustom;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final refusal = this.refusal;

    return ListView(
      children: [
        Text(
          l10n.whitelistSubtitle(displayPath),
          style: HoopixType.callout.copyWith(color: palette.labelSecondary),
        ),
        if (selection.isDefault) ...[
          const SizedBox(height: HoopixSpacing.xs),
          Text(
            l10n.whitelistDefaultsNote,
            style: HoopixType.callout.copyWith(color: palette.labelTertiary),
          ),
        ],
        if (saveError != null) ...[
          const SizedBox(height: HoopixSpacing.sm),
          Text(
            l10n.whitelistSaveFailed('$saveError'),
            style: HoopixType.callout.copyWith(color: palette.danger),
          ),
        ],
        for (final category in WhitelistCategory.values) ...[
          const SizedBox(height: HoopixSpacing.lg),
          _Heading(_categoryLabel(l10n, category)),
          for (final item in whitelistCatalog)
            if (item.category == category)
              _CatalogRow(
                item: item,
                checked: selection.isChecked(item),
                locked: selection.isAlwaysProtected(item),
                onToggle: () => onToggle(item),
              ),
        ],
        const SizedBox(height: HoopixSpacing.lg),
        _Heading(l10n.whitelistCustomTitle),
        if (selection.custom.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              l10n.whitelistCustomEmpty,
              style: HoopixType.body.copyWith(color: palette.labelTertiary),
            ),
          ),
        for (final line in selection.custom)
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  line,
                  style: HoopixType.body.copyWith(color: palette.labelPrimary),
                ),
              ),
              IconButton(
                tooltip: l10n.whitelistRemove,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.remove_circle_outline,
                  size: 18,
                  color: palette.labelSecondary,
                ),
                onPressed: () => onRemoveCustom(line),
              ),
            ],
          ),
        const SizedBox(height: HoopixSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: customField,
                style: HoopixType.body.copyWith(color: palette.labelPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.whitelistCustomHint,
                  errorText: refusal == null
                      ? null
                      : _refusalLabel(l10n, refusal),
                ),
                onSubmitted: (_) => onAddCustom(),
              ),
            ),
            const SizedBox(width: HoopixSpacing.sm),
            TextButton(
              onPressed: onAddCustom,
              style: TextButton.styleFrom(foregroundColor: palette.brand),
              child: Text(l10n.whitelistAdd, style: HoopixType.body),
            ),
          ],
        ),
      ],
    );
  }

  static String _categoryLabel(
    AppLocalizations l10n,
    WhitelistCategory category,
  ) => switch (category) {
    WhitelistCategory.systemCache => l10n.whitelistCategorySystemCache,
    WhitelistCategory.ideCache => l10n.whitelistCategoryIdeCache,
    WhitelistCategory.aiMlCache => l10n.whitelistCategoryAiMlCache,
    WhitelistCategory.compilerCache => l10n.whitelistCategoryCompilerCache,
    WhitelistCategory.packageManager => l10n.whitelistCategoryPackageManager,
    WhitelistCategory.browserCache => l10n.whitelistCategoryBrowserCache,
    WhitelistCategory.networkTools => l10n.whitelistCategoryNetworkTools,
    WhitelistCategory.containerCache => l10n.whitelistCategoryContainerCache,
    WhitelistCategory.appCache => l10n.whitelistCategoryAppCache,
  };

  /// The whitelist parser's reasons, in the user's language; an unknown
  /// one is shown as it is rather than hidden.
  static String _refusalLabel(AppLocalizations l10n, String reason) =>
      switch (reason) {
        'Path traversal not allowed' => l10n.whitelistRefusedTraversal,
        'Invalid path format' => l10n.whitelistRefusedInvalid,
        'Must be absolute path' => l10n.whitelistRefusedNotAbsolute,
        'Consecutive slashes' => l10n.whitelistRefusedSlashes,
        'Protected system path' => l10n.whitelistRefusedSystem,
        _ => reason,
      };
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: HoopixSpacing.xs),
    child: Text(
      text,
      style: HoopixType.body.copyWith(
        color: context.palette.labelPrimary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.item,
    required this.checked,
    required this.locked,
    required this.onToggle,
  });

  final WhitelistCatalogItem item;
  final bool checked;
  final bool locked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: checked,
              activeColor: palette.brand,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onChanged: locked ? null : (_) => onToggle(),
            ),
          ),
          const SizedBox(width: HoopixSpacing.sm),
          Expanded(
            child: Tooltip(
              message: item.pattern,
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HoopixType.body.copyWith(color: palette.labelPrimary),
              ),
            ),
          ),
          if (locked)
            Text(
              l10n.whitelistAlwaysProtected,
              style: HoopixType.caption.copyWith(color: palette.labelTertiary),
            ),
        ],
      ),
    );
  }
}
