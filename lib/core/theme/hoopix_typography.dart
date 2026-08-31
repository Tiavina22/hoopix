import 'package:flutter/widgets.dart';

/// Type scale, following Apple's macOS HIG sizes, set in Manrope.
///
/// Manrope is a geometric sans with a large x-height, so tracking is a little
/// tighter than the scale would be in San Francisco and weights sit one step
/// lighter than their Material equivalents.
///
/// Note on numerals: Manrope ships no `tnum` (tabular figures) feature, so
/// digits have proportional widths and a value refreshing every couple of
/// seconds would visibly wobble. `TabularText` solves that in layout instead
/// of relying on a font feature that isn't there — use it for any number that
/// updates live.
abstract final class HoopixType {
  static const fontFamily = 'Manrope';

  static const largeTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  static const title = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static const headline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 19 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
  );

  static const callout = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
  );

  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
  );

  /// Small uppercase label used for card titles.
  static const cardTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.7,
  );

  /// The big number inside a ring gauge.
  static const metric = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: 28 / 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
  );

  /// Secondary live numbers (throughput, percentages in lists).
  static const numeric = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
  );

  static const numericCaption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
  );
}
