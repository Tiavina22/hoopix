import 'package:flutter/material.dart';

/// Raw color ramps. Nothing in the app reads these directly — screens read
/// semantic roles from [HoopixPalette] instead, so a palette change never
/// means hunting for hardcoded hexes.
abstract final class HoopixColorRamp {
  /// Hoopix's brand hue: an Apple Music rose. Kept as a full ramp rather than
  /// a single hex so tints, fills, and pressed states stay in the same family.
  static const rose50 = Color(0xFFFFF1F4);
  static const rose100 = Color(0xFFFFE7EC);
  static const rose200 = Color(0xFFFFC7D2);
  static const rose300 = Color(0xFFFF97AB);
  static const rose400 = Color(0xFFFF6B85);
  static const rose500 = Color(0xFFFB6B80);
  static const rose600 = Color(0xFFFA2D48);
  static const rose700 = Color(0xFFC8102E);

  /// Near-neutral grays carrying a faint rose undertone, so the chrome sits
  /// under the brand instead of fighting it.
  static const sand0 = Color(0xFFFFFFFF);
  static const sand50 = Color(0xFFFBF9FA);
  static const sand100 = Color(0xFFF3F0F2);
  static const sand200 = Color(0xFFE9E5E7);
  static const ink300 = Color(0xFF979296);
  static const ink500 = Color(0xFF676266);
  static const ink900 = Color(0xFF1B1A1C);

  /// True black, used only for the dark-mode window background — every
  /// other dark surface stays on the `night*` ramp so panels remain
  /// distinguishable against it.
  static const trueBlack = Color(0xFF000000);

  static const night0 = Color(0xFF141315);
  static const night50 = Color(0xFF1A191B);
  static const night100 = Color(0xFF1E1D20);
  static const night200 = Color(0xFF232126);
  static const night300 = Color(0xFF322F35);
  static const mist300 = Color(0xFF78727A);
  static const mist500 = Color(0xFFA6A0A8);
  static const mist900 = Color(0xFFF4F1F4);

  /// Status hues stay deliberately *outside* the rose family. The brand is a
  /// pink-red, so the critical color is pushed toward vermilion — hue is what
  /// separates "brand" from "warning" here, since a second pink-red would
  /// read as decoration rather than a signal.
  static const successLight = Color(0xFF2E9E62);
  static const successDark = Color(0xFF3DD68C);
  static const warningLight = Color(0xFFE0A020);
  static const warningDark = Color(0xFFF5C451);
  static const dangerLight = Color(0xFFD93A25);
  static const dangerDark = Color(0xFFFF7043);
}

/// Semantic color roles, resolved per brightness and exposed as a
/// [ThemeExtension] so widgets read `context.palette.surface` instead of
/// branching on `Theme.of(context).brightness` themselves.
@immutable
class HoopixPalette extends ThemeExtension<HoopixPalette> {
  const HoopixPalette({
    required this.brand,
    required this.brandStrong,
    required this.brandSubtle,
    required this.windowBackground,
    required this.sidebarBackground,
    required this.surface,
    required this.surfaceSubtle,
    required this.separator,
    required this.labelPrimary,
    required this.labelSecondary,
    required this.labelTertiary,
    required this.track,
    required this.success,
    required this.warning,
    required this.danger,
  });

  factory HoopixPalette.light() => const HoopixPalette(
    brand: HoopixColorRamp.rose600,
    brandStrong: HoopixColorRamp.rose500,
    brandSubtle: HoopixColorRamp.rose100,
    windowBackground: HoopixColorRamp.sand0,
    sidebarBackground: HoopixColorRamp.sand100,
    surface: HoopixColorRamp.sand0,
    surfaceSubtle: HoopixColorRamp.sand50,
    separator: Color(0x14000000),
    labelPrimary: HoopixColorRamp.ink900,
    labelSecondary: HoopixColorRamp.ink500,
    labelTertiary: HoopixColorRamp.ink300,
    track: HoopixColorRamp.sand200,
    success: HoopixColorRamp.successLight,
    warning: HoopixColorRamp.warningLight,
    danger: HoopixColorRamp.dangerLight,
  );

  factory HoopixPalette.dark() => const HoopixPalette(
    brand: HoopixColorRamp.rose400,
    brandStrong: HoopixColorRamp.rose300,
    brandSubtle: Color(0xFF3A1C24),
    windowBackground: HoopixColorRamp.trueBlack,
    sidebarBackground: HoopixColorRamp.night50,
    surface: HoopixColorRamp.night200,
    surfaceSubtle: HoopixColorRamp.night100,
    separator: Color(0x1AFFFFFF),
    labelPrimary: HoopixColorRamp.mist900,
    labelSecondary: HoopixColorRamp.mist500,
    labelTertiary: HoopixColorRamp.mist300,
    track: HoopixColorRamp.night300,
    success: HoopixColorRamp.successDark,
    warning: HoopixColorRamp.warningDark,
    danger: HoopixColorRamp.dangerDark,
  );

  final Color brand;
  final Color brandStrong;
  final Color brandSubtle;
  final Color windowBackground;
  final Color sidebarBackground;
  final Color surface;
  final Color surfaceSubtle;
  final Color separator;
  final Color labelPrimary;
  final Color labelSecondary;
  final Color labelTertiary;
  final Color track;
  final Color success;
  final Color warning;
  final Color danger;

  /// Threshold color for a 0..1 usage meter: healthy, watch, critical.
  /// Used for storage, where "nearly full" is genuinely actionable.
  Color meterColor(double fraction) {
    if (fraction >= 0.9) return danger;
    if (fraction >= 0.7) return warning;
    return success;
  }

  @override
  HoopixPalette copyWith({
    Color? brand,
    Color? brandStrong,
    Color? brandSubtle,
    Color? windowBackground,
    Color? sidebarBackground,
    Color? surface,
    Color? surfaceSubtle,
    Color? separator,
    Color? labelPrimary,
    Color? labelSecondary,
    Color? labelTertiary,
    Color? track,
    Color? success,
    Color? warning,
    Color? danger,
  }) {
    return HoopixPalette(
      brand: brand ?? this.brand,
      brandStrong: brandStrong ?? this.brandStrong,
      brandSubtle: brandSubtle ?? this.brandSubtle,
      windowBackground: windowBackground ?? this.windowBackground,
      sidebarBackground: sidebarBackground ?? this.sidebarBackground,
      surface: surface ?? this.surface,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      separator: separator ?? this.separator,
      labelPrimary: labelPrimary ?? this.labelPrimary,
      labelSecondary: labelSecondary ?? this.labelSecondary,
      labelTertiary: labelTertiary ?? this.labelTertiary,
      track: track ?? this.track,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  HoopixPalette lerp(HoopixPalette? other, double t) {
    if (other == null) return this;
    return HoopixPalette(
      brand: Color.lerp(brand, other.brand, t)!,
      brandStrong: Color.lerp(brandStrong, other.brandStrong, t)!,
      brandSubtle: Color.lerp(brandSubtle, other.brandSubtle, t)!,
      windowBackground: Color.lerp(
        windowBackground,
        other.windowBackground,
        t,
      )!,
      sidebarBackground: Color.lerp(
        sidebarBackground,
        other.sidebarBackground,
        t,
      )!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      labelPrimary: Color.lerp(labelPrimary, other.labelPrimary, t)!,
      labelSecondary: Color.lerp(labelSecondary, other.labelSecondary, t)!,
      labelTertiary: Color.lerp(labelTertiary, other.labelTertiary, t)!,
      track: Color.lerp(track, other.track, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
