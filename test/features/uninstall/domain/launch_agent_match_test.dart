import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/uninstall/domain/entities/launch_agent_match.dart';

void main() {
  group('launchAgentNameMatchesBundleId', () {
    test('matches the exact bundle id plist and its dotted helpers', () {
      expect(
        launchAgentNameMatchesBundleId(
          'com.example.app.plist',
          'com.example.app',
        ),
        isTrue,
      );
      expect(
        launchAgentNameMatchesBundleId(
          'com.example.app.helper.plist',
          'com.example.app',
        ),
        isTrue,
      );
    });

    test('never matches past a non-dot boundary or a vendor prefix', () {
      expect(
        launchAgentNameMatchesBundleId(
          'com.example.application.plist',
          'com.example.app',
        ),
        isFalse,
      );
      expect(
        launchAgentNameMatchesBundleId(
          'com.example.other.plist',
          'com.example.app',
        ),
        isFalse,
      );
    });

    test('requires a .plist and a real reverse-DNS bundle id', () {
      expect(
        launchAgentNameMatchesBundleId(
          'com.example.app.helper',
          'com.example.app',
        ),
        isFalse,
      );
      expect(
        launchAgentNameMatchesBundleId('unknown.plist', 'unknown'),
        isFalse,
      );
      expect(launchAgentNameMatchesBundleId('.plist', ''), isFalse);
    });
  });

  group('launchAgentNameMatchesAppName', () {
    test('matches a plist whose name contains the display name', () {
      expect(
        launchAgentNameMatchesAppName(
          'net.vendor.Dropbox.agent.plist',
          'Dropbox',
        ),
        isTrue,
      );
    });

    test('is case-sensitive, like find -name', () {
      expect(
        launchAgentNameMatchesAppName('net.vendor.dropbox.plist', 'Dropbox'),
        isFalse,
      );
    });

    test('skips names shorter than five characters', () {
      expect(
        launchAgentNameMatchesAppName('us.zoom.Zoom.plist', 'Zoom'),
        isFalse,
      );
    });

    test('skips generic words, in any case', () {
      expect(
        launchAgentNameMatchesAppName('com.vendor.Helper.plist', 'Helper'),
        isFalse,
      );
      expect(
        launchAgentNameMatchesAppName('com.vendor.helper.plist', 'helper'),
        isFalse,
      );
    });

    test("never matches Apple's own agents", () {
      expect(
        launchAgentNameMatchesAppName('com.apple.Dropbox.plist', 'Dropbox'),
        isFalse,
      );
    });

    test('only matches inside the name, not the .plist suffix', () {
      expect(launchAgentNameMatchesAppName('x.plist', 'plist'), isFalse);
      expect(
        launchAgentNameMatchesAppName('com.vendor.Dropbox', 'Dropbox'),
        isFalse,
      );
    });
  });
}
