import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_colors.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';

/// Builds the app's [ThemeData] from the design tokens. Material is used only
/// as the rendering substrate — every visible surface, color, and text style
/// comes from [HoopixPalette] and [HoopixType], so the app doesn't look like
/// stock Material.
abstract final class HoopixTheme {
  static ThemeData light() => _build(Brightness.light, HoopixPalette.light());

  static ThemeData dark() => _build(Brightness.dark, HoopixPalette.dark());

  static ThemeData _build(Brightness brightness, HoopixPalette palette) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);

    return base.copyWith(
      extensions: [palette],
      scaffoldBackgroundColor: palette.windowBackground,
      canvasColor: palette.windowBackground,
      colorScheme: base.colorScheme.copyWith(
        primary: palette.brand,
        surface: palette.surface,
        error: palette.danger,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: HoopixType.fontFamily,
        bodyColor: palette.labelPrimary,
        displayColor: palette.labelPrimary,
      ),
      dividerTheme: DividerThemeData(
        color: palette.separator,
        thickness: 1,
        space: 1,
      ),
      // Trackpad-friendly, macOS-style overlay scrollbars.
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.all(palette.labelTertiary),
      ),
    );
  }
}

/// Ergonomic access to the semantic palette: `context.palette.brand`.
///
/// Falls back to the brightness-appropriate default when the extension is
/// missing, so a widget rendered outside [HoopixTheme] — a test harness, a
/// preview, a future embed — degrades to correct colors instead of throwing.
extension HoopixPaletteX on BuildContext {
  HoopixPalette get palette {
    final theme = Theme.of(this);
    return theme.extension<HoopixPalette>() ??
        (theme.brightness == Brightness.dark
            ? HoopixPalette.dark()
            : HoopixPalette.light());
  }
}
