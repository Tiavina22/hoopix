import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/uninstall/domain/entities/bundle_id_boundary.dart';

void main() {
  group('nameStartsWithBundleIdBoundary', () {
    test('matches the exact bundle id', () {
      expect(
        nameStartsWithBundleIdBoundary('com.example.App', 'com.example.App'),
        isTrue,
      );
    });

    test('matches a dot-suffixed extension', () {
      expect(
        nameStartsWithBundleIdBoundary(
          'com.example.App.plist',
          'com.example.App',
        ),
        isTrue,
      );
    });

    test('never matches a raw substring without a dot boundary', () {
      expect(
        nameStartsWithBundleIdBoundary(
          'com.example.AppHelper',
          'com.example.App',
        ),
        isFalse,
      );
    });

    test('reads only the basename of a full path', () {
      expect(
        nameStartsWithBundleIdBoundary(
          '/some/dir/com.example.App.plist',
          'com.example.App',
        ),
        isTrue,
      );
    });

    test('rejects a bundle id that is not reverse-DNS shaped', () {
      expect(nameStartsWithBundleIdBoundary('MyApp', 'MyApp'), isFalse);
      expect(nameStartsWithBundleIdBoundary('unknown', 'unknown'), isFalse);
    });
  });

  group('nameHasBundleIdBoundary', () {
    test('matches everything nameStartsWithBundleIdBoundary does', () {
      expect(
        nameHasBundleIdBoundary('com.example.App', 'com.example.App'),
        isTrue,
      );
    });

    test('matches a dot-anchored suffix segment', () {
      expect(
        nameHasBundleIdBoundary('TEAMID.com.example.App', 'com.example.App'),
        isTrue,
      );
    });

    test('matches a dot-anchored middle segment', () {
      expect(
        nameHasBundleIdBoundary(
          'TEAMID.com.example.App.extra',
          'com.example.App',
        ),
        isTrue,
      );
    });

    test('never matches a raw substring without dot boundaries', () {
      expect(
        nameHasBundleIdBoundary('TEAMIDcom.example.App', 'com.example.App'),
        isFalse,
      );
    });
  });
}
