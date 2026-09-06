import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/uninstall/domain/entities/generic_app_name.dart';

void main() {
  test('matches a generic word case-insensitively', () {
    expect(isGenericAppName('System'), isTrue);
    expect(isGenericAppName('system'), isTrue);
    expect(isGenericAppName('SYSTEM'), isTrue);
  });

  test('does not match an ordinary distinctive app name', () {
    expect(isGenericAppName('MyApp'), isFalse);
    expect(isGenericAppName('Photoshop'), isFalse);
  });

  test('does not partially match a name only containing a generic word', () {
    // "Store" is generic, but "App Store Connect" as a whole is not.
    expect(isGenericAppName('App Store Connect'), isFalse);
  });
}
