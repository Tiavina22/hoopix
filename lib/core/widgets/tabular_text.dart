import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Renders text with every digit in a cell as wide as the widest digit,
/// giving tabular (monospaced) numerals in a font that has no `tnum` feature.
///
/// Manrope is one such font. Without this, a live value like `9%` → `10%` →
/// `8%` shifts width on every refresh and the dashboard visibly twitches
/// twice a second. Non-digit characters keep their natural width, so units
/// and separators still sit tight against the number.
class TabularText extends StatelessWidget {
  const TabularText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final digitWidth = _widestDigitWidth(style, scaler);

    // Laying each glyph out separately would otherwise make assistive tech
    // announce "1, 5, %" instead of "15%", so the whole string is published
    // as one semantics node and the per-character children are excluded.
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: textAlign == TextAlign.right
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          for (final character in text.split(''))
            _isDigit(character)
                ? SizedBox(
                    width: digitWidth,
                    child: Text(
                      character,
                      style: style,
                      textAlign: TextAlign.center,
                    ),
                  )
                : Text(character, style: style),
        ],
      ),
    );
  }

  static bool _isDigit(String character) {
    if (character.length != 1) return false;
    final code = character.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static double _widestDigitWidth(TextStyle style, TextScaler scaler) {
    var widest = 0.0;
    for (var digit = 0; digit <= 9; digit++) {
      final painter = TextPainter(
        text: TextSpan(text: '$digit', style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }
}
