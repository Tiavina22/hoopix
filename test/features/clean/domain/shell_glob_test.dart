import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/domain/entities/shell_glob.dart';

void main() {
  test('a pattern with no wildcards matches only itself', () {
    expect(matchesShellGlob('com.apple.finder', 'com.apple.finder'), isTrue);
    expect(matchesShellGlob('com.apple.finders', 'com.apple.finder'), isFalse);
    // The whole string must match, not a fragment of it.
    expect(matchesShellGlob('x.com.apple.finder', 'com.apple.finder'), isFalse);
  });

  test('* spans anything, including separators', () {
    expect(matchesShellGlob('com.apple.Settings', 'com.apple.*'), isTrue);
    expect(matchesShellGlob('/a/b/c', '/a/*'), isTrue);
    expect(matchesShellGlob('com.apple.', 'com.apple.*'), isTrue);
    expect(matchesShellGlob('com.google.x', 'com.apple.*'), isFalse);
  });

  test('? matches exactly one character', () {
    expect(matchesShellGlob('cat', 'c?t'), isTrue);
    expect(matchesShellGlob('ct', 'c?t'), isFalse);
    expect(matchesShellGlob('coat', 'c?t'), isFalse);
  });

  test('character classes match one of their members', () {
    expect(matchesShellGlob('SystemSettings', '[Ss]ystem[Ss]ettings'), isTrue);
    expect(matchesShellGlob('systemsettings', '[Ss]ystem[Ss]ettings'), isTrue);
    expect(matchesShellGlob('Xystemsettings', '[Ss]ystem[Ss]ettings'), isFalse);
  });

  test('classes support ranges and negation', () {
    expect(matchesShellGlob('file7', 'file[0-9]'), isTrue);
    expect(matchesShellGlob('filex', 'file[0-9]'), isFalse);
    expect(matchesShellGlob('filex', 'file[!0-9]'), isTrue);
    expect(matchesShellGlob('file7', 'file[!0-9]'), isFalse);
  });

  test('matching is case-sensitive', () {
    // Mole spells case-insensitivity out as classes; folding it here would
    // silently widen every rule.
    expect(matchesShellGlob('com.apple.settings', 'com.apple.Settings'), isFalse);
  });

  test('regex metacharacters in a pattern are literal', () {
    expect(matchesShellGlob('a.b', 'a.b'), isTrue);
    expect(matchesShellGlob('axb', 'a.b'), isFalse);
    expect(matchesShellGlob(r'a$b', r'a$b'), isTrue);
    expect(matchesShellGlob('a+b', 'a+b'), isTrue);
    expect(matchesShellGlob('aab', 'a+b'), isFalse);
  });

  test('an empty pattern matches nothing at all', () {
    expect(matchesShellGlob('', ''), isFalse);
    expect(matchesShellGlob('anything', ''), isFalse);
  });

  test('an unterminated class is a literal bracket', () {
    expect(matchesShellGlob('[abc', '[abc'), isTrue);
  });

  test('a real Mole pattern behaves as written', () {
    expect(
      matchesShellGlob('/Users/t/Library/Caches/Adobe Photoshop', r'*/Library/Caches/Adobe *'),
      isTrue,
    );
    expect(
      matchesShellGlob('/Users/t/Library/Caches/Adobe', r'*/Library/Caches/Adobe *'),
      isFalse,
    );
  });
}
