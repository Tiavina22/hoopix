import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regenerating the `macos/` folder (`flutter create`) silently puts the
/// template identifier and copyright back. The identifier is what macOS keys
/// permissions and preferences on, so shipping the placeholder means every
/// user's grants would move when it is finally fixed.
void main() {
  final config = File(
    'macos/Runner/Configs/AppInfo.xcconfig',
  ).readAsStringSync();

  test('the macOS app ships the Lyrify identifier, not the template one', () {
    expect(config, contains('PRODUCT_BUNDLE_IDENTIFIER = com.lyrify.hoopix\n'));
    expect(config, isNot(contains('com.example')));
  });

  test('the test target uses the same identifier family', () {
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(project, contains('com.lyrify.hoopix.RunnerTests'));
    expect(project, isNot(contains('com.example')));
  });

  test('the copyright names the author, not a placeholder', () {
    expect(config, contains('Tiavina Ramilison'));
  });

  test('no platform runner still carries the template identity', () {
    for (final path in ['linux/CMakeLists.txt', 'windows/runner/Runner.rc']) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('com.example')),
        reason: path,
      );
    }
  });
}
