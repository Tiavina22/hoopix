import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_colors.dart';

/// The Hoopix mark: an open ring with a square "pixel" resting in its gap.
///
/// The idea is the name — *hoop* + *pix* — and it doubles as the product's
/// core visual, since every metric on the dashboard is drawn as a ring gauge.
/// The mark is one geometric idea with no illustration or bevel, so it stays
/// legible from a 16pt menu-bar glyph up to a 1024pt icon.
///
/// Defined once as a painter so the sidebar mark and the exported app icon
/// are the same vector art rather than two drifting copies.
class HoopixLogo extends StatelessWidget {
  const HoopixLogo({super.key, this.size = 26, this.color, this.gradient});

  final double size;

  /// Solid paint for the mark. Ignored when [gradient] is set.
  final Color? color;

  /// Gradient paint for the mark, used for the app icon's white-on-rose
  /// treatment and the brand's rose-on-light treatment.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: HoopixMarkPainter(
          color: color ?? HoopixColorRamp.rose600,
          gradient: gradient,
        ),
      ),
    );
  }
}

/// Paints the Hoopix mark into any square box.
class HoopixMarkPainter extends CustomPainter {
  const HoopixMarkPainter({required this.color, this.gradient});

  final Color color;
  final Gradient? gradient;

  /// Where the missing pixel sits, on the upper-right diagonal.
  ///
  /// Off-axis on purpose: a ring broken at twelve o'clock is the universal
  /// power symbol, and a ring with a tapered tail is the universal loading
  /// spinner. A closed hoop interrupted by one square keeps clear of both.
  static const _notchAngle = -math.pi / 4;

  @override
  void paint(Canvas canvas, Size size) {
    final extent = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = extent * 0.155;
    final radius = (extent - strokeWidth) / 2 * 0.92;

    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    if (gradient != null) {
      paint.shader = gradient!.createShader(
        Rect.fromCircle(center: center, radius: extent / 2),
      );
    } else {
      paint.color = color;
    }

    canvas.drawPath(
      _hoopMinusPixel(
        center: center,
        radius: radius,
        strokeWidth: strokeWidth,
      ),
      paint,
    );
  }

  /// A closed hoop with exactly one square "pixel" subtracted from its
  /// stroke — the name (*hoop* + *pix*) and the product's job in one shape.
  ///
  /// The notch is cut rather than drawn as a gap so both of its edges stay
  /// crisp and square, which is what distinguishes the mark from a ring that
  /// merely stops short.
  Path _hoopMinusPixel({
    required Offset center,
    required double radius,
    required double strokeWidth,
  }) {
    final hoop = Path.combine(
      PathOperation.difference,
      Path()
        ..addOval(
          Rect.fromCircle(center: center, radius: radius + strokeWidth / 2),
        ),
      Path()
        ..addOval(
          Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        ),
    );

    // The cut is rotated to the ring's tangent so both faces come out
    // perpendicular to the stroke. Left axis-aligned, a notch on the diagonal
    // clips the outer edge at a shallow angle and leaves a stepped, chipped
    // silhouette instead of one cleanly removed segment.
    final notchExtent = strokeWidth * 1.18;
    final notchCenter =
        center +
        Offset(math.cos(_notchAngle), math.sin(_notchAngle)) * radius;

    final notch = Path()
      ..addRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: notchExtent,
          height: notchExtent,
        ),
      );

    final placement = Matrix4.identity()
      ..translateByDouble(notchCenter.dx, notchCenter.dy, 0, 1)
      ..rotateZ(_notchAngle + math.pi / 2);

    return Path.combine(
      PathOperation.difference,
      hoop,
      notch.transform(placement.storage),
    );
  }

  @override
  bool shouldRepaint(HoopixMarkPainter old) =>
      old.color != color || old.gradient != gradient;
}

/// The macOS app icon: the mark in white on the brand's rose gradient,
/// inside a rounded square.
///
/// Drawn at Apple's macOS icon proportions — the art occupies roughly 80% of
/// the canvas, leaving the margin the system expects — so it sits at the same
/// visual weight as native icons in the Dock instead of looking oversized.
class HoopixAppIconPainter extends CustomPainter {
  const HoopixAppIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final canvasExtent = size.shortestSide;
    final bodyExtent = canvasExtent * 0.805;
    final origin = (canvasExtent - bodyExtent) / 2;
    final body = Rect.fromLTWH(origin, origin, bodyExtent, bodyExtent);

    // 22.37% of the width is the standard approximation of the continuous
    // corner Apple uses for app icons.
    final squircle = RRect.fromRectAndRadius(
      body,
      Radius.circular(bodyExtent * 0.2237),
    );

    canvas.drawRRect(
      squircle,
      Paint()
        ..isAntiAlias = true
        ..shader =
            const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [HoopixColorRamp.rose500, HoopixColorRamp.rose700],
            ).createShader(body),
    );

    canvas.save();
    canvas.translate(body.left, body.top);
    const markScale = 0.62;
    final markExtent = bodyExtent * markScale;
    final markOrigin = (bodyExtent - markExtent) / 2;
    canvas.translate(markOrigin, markOrigin);
    const HoopixMarkPainter(color: Colors.white).paint(
      canvas,
      Size(markExtent, markExtent),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(HoopixAppIconPainter oldDelegate) => false;
}
