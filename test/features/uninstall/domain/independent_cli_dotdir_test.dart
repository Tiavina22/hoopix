import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/uninstall/domain/entities/independent_cli_dotdir.dart';

const _home = '/Users/tester';

void main() {
  test('protects ~/.claude from a same-named GUI app (issue #993)', () {
    expect(pathBelongsToIndependentCli('$_home/.claude', home: _home), isTrue);
  });

  test('protects ~/.local/share/opencode', () {
    expect(
      pathBelongsToIndependentCli('$_home/.local/share/opencode', home: _home),
      isTrue,
    );
  });

  test('is case-insensitive, matching case-insensitive APFS collisions', () {
    expect(pathBelongsToIndependentCli('$_home/Claude', home: _home), isTrue);
  });

  test('matches with or without a leading dot', () {
    expect(pathBelongsToIndependentCli('$_home/codex', home: _home), isTrue);
    expect(pathBelongsToIndependentCli('$_home/.codex', home: _home), isTrue);
  });

  test('never matches a name outside the fixed list', () {
    expect(
      pathBelongsToIndependentCli('$_home/.someOtherTool', home: _home),
      isFalse,
    );
  });

  test('never matches when the parent is not a shared root', () {
    expect(
      pathBelongsToIndependentCli('$_home/Projects/claude', home: _home),
      isFalse,
    );
  });

  test('matches under .config and .cache too', () {
    expect(
      pathBelongsToIndependentCli('$_home/.config/gemini', home: _home),
      isTrue,
    );
    expect(
      pathBelongsToIndependentCli('$_home/.cache/codex', home: _home),
      isTrue,
    );
  });
}
