/// Renders the Hoopix brand art to PNG.
///
/// This lives outside `test/` so it is not part of the normal suite — it is a
/// generator, run on demand when the mark changes:
///
/// ```bash
/// flutter test tool/generate_app_icon_test.dart
/// dart run flutter_launcher_icons
/// ```
///
/// Keeping the icon generated from [HoopixMarkPainter] means the app icon and
/// the in-app mark can never drift apart.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/brand/hoopix_logo.dart';
import 'package:hoopix/core/theme/hoopix_colors.dart';

Future<void> _writePng(
  String path,
  Size size,
  void Function(Canvas canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, size.width, size.height),
  );
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());

  picture.dispose();
  image.dispose();
}

void main() {
  testWidgets('writes the 1024pt macOS app icon', (tester) async {
    const size = Size(1024, 1024);
    await _writePng(
      'assets/icon/hoopix_icon.png',
      size,
      (canvas) => const HoopixAppIconPainter().paint(canvas, size),
    );

    expect(File('assets/icon/hoopix_icon.png').existsSync(), isTrue);
  });

  testWidgets('writes a size-ladder proof sheet for design review', (
    tester,
  ) async {
    // The mark has to survive the Dock, the menu bar, and a favicon. Render
    // the real sizes side by side rather than trusting that a 1024pt render
    // scales down cleanly.
    const sizes = [16.0, 24.0, 32.0, 64.0, 128.0, 256.0];
    const gap = 24.0;
    const padding = 32.0;

    final width =
        sizes.fold<double>(0, (sum, size) => sum + size + gap) -
        gap +
        padding * 2;
    const height = 256.0 + padding * 2;

    await _writePng('build/brand/size_ladder.png', Size(width, height), (
      canvas,
    ) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height),
        Paint()..color = const Color(0xFFFBF9FA),
      );

      var offsetX = padding;
      for (final size in sizes) {
        canvas.save();
        // Bottom-align the ladder so the sizes read as a stepped series.
        canvas.translate(offsetX, padding + (256.0 - size));
        const HoopixMarkPainter(
          color: HoopixColorRamp.rose600,
        ).paint(canvas, Size(size, size));
        canvas.restore();
        offsetX += size + gap;
      }
    });

    expect(File('build/brand/size_ladder.png').existsSync(), isTrue);
  });

  testWidgets('writes an app-icon proof at Dock sizes', (tester) async {
    const sizes = [32.0, 64.0, 128.0, 256.0];
    const gap = 24.0;
    const padding = 32.0;

    final width =
        sizes.fold<double>(0, (sum, size) => sum + size + gap) -
        gap +
        padding * 2;
    const height = 256.0 + padding * 2;

    await _writePng('build/brand/icon_ladder.png', Size(width, height), (
      canvas,
    ) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height),
        Paint()..color = const Color(0xFFE9E5E7),
      );

      var offsetX = padding;
      for (final size in sizes) {
        canvas.save();
        canvas.translate(offsetX, padding + (256.0 - size));
        const HoopixAppIconPainter().paint(canvas, Size(size, size));
        canvas.restore();
        offsetX += size + gap;
      }
    });

    expect(File('build/brand/icon_ladder.png').existsSync(), isTrue);
  });
}
