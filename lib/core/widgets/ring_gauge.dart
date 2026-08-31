import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/widgets/tabular_text.dart';

/// A circular usage gauge — the app's primary way of showing a 0..1 value.
///
/// Values animate to their new position instead of snapping, so a dashboard
/// refreshing every couple of seconds reads as continuous rather than
/// twitchy.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.value,
    required this.centerLabel,
    this.size = 96,
    this.strokeWidth = 9,
    this.color,
  });

  /// Fraction filled, 0..1. Values outside the range are clamped.
  final double value;
  final String centerLabel;
  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final start = color ?? palette.brand;
    final end = color ?? palette.brandStrong;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              value: animated,
              strokeWidth: strokeWidth,
              trackColor: palette.track,
              startColor: start,
              endColor: end,
            ),
            child: Center(
              child: TabularText(
                centerLabel,
                style: HoopixType.metric.copyWith(color: palette.labelPrimary),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.strokeWidth,
    required this.trackColor,
    required this.startColor,
    required this.endColor,
  });

  final double value;
  final double strokeWidth;
  final Color trackColor;
  final Color startColor;
  final Color endColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    if (value <= 0) return;

    // Start at 12 o'clock and sweep clockwise, the direction people read a
    // dial. The gradient rotates with it so the cap colors stay consistent.
    const startAngle = -math.pi / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      bounds,
      startAngle,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [startColor, endColor],
          transform: const GradientRotation(startAngle),
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) {
    return old.value != value ||
        old.strokeWidth != strokeWidth ||
        old.trackColor != trackColor ||
        old.startColor != startColor ||
        old.endColor != endColor;
  }
}

/// Slim horizontal usage bar, used where a ring would be too heavy (storage
/// rows, battery level). Shares the ring's animation timing so the whole
/// dashboard moves as one.
class LinearMeter extends StatelessWidget {
  const LinearMeter({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
  });

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: palette.track)),
                FractionallySizedBox(
                  widthFactor: animated,
                  child: ColoredBox(color: color ?? palette.brand),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
