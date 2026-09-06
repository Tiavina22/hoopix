import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/uninstall/domain/entities/uninstall_protection.dart';

void main() {
  test('protects an ordinary system-critical bundle', () {
    expect(shouldProtectFromUninstall('com.apple.finder'), isTrue);
    expect(shouldProtectFromUninstall('com.apple.dock'), isTrue);
  });

  test('never protects an ordinary third-party app', () {
    expect(shouldProtectFromUninstall('com.example.MyApp'), isFalse);
  });

  test('the uninstallable-apps override wins even over a critical match', () {
    // com.apple.dt.* is the override; if a future critical-bundle entry
    // ever matched Xcode's own id, this override must still take priority.
    expect(shouldProtectFromUninstall('com.apple.dt.Xcode'), isFalse);
    expect(shouldProtectFromUninstall('com.apple.FinalCutPro'), isFalse);
    expect(shouldProtectFromUninstall('com.apple.logic10'), isFalse);
  });

  test('unknown is never protected', () {
    expect(shouldProtectFromUninstall('unknown'), isFalse);
  });
}
