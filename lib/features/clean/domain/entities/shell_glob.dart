/// Matches a string against a shell pattern the way bash's `[[ x == p ]]`
/// and `case` do, because every protection rule ported from Mole is written
/// as one.
///
/// Supports `*`, `?`, and `[...]` classes including ranges and `[!...]` /
/// `[^...]` negation. Matching is case-sensitive: Mole's rules encode
/// case-insensitivity explicitly as classes (`*[Ss]ystem[Ss]ettings*`), and
/// silently folding case here would widen every one of them.
bool matchesShellGlob(String value, String pattern) {
  if (pattern.isEmpty) return false;
  return _compiled
      .putIfAbsent(pattern, () => RegExp('^${_translate(pattern)}\$'))
      .hasMatch(value);
}

/// Patterns are fixed constants reused across thousands of paths, so each is
/// translated once.
final _compiled = <String, RegExp>{};

String _translate(String pattern) {
  final out = StringBuffer();
  var index = 0;

  while (index < pattern.length) {
    final char = pattern[index];
    switch (char) {
      case '*':
        out.write('.*');
        index++;
      case '?':
        out.write('.');
        index++;
      case '[':
        final className = _readClass(pattern, index);
        if (className == null) {
          // An unterminated `[` is a literal bracket in shell too.
          out.write(RegExp.escape('['));
          index++;
        } else {
          out.write(className.regex);
          index = className.end;
        }
      case r'\':
        // Escapes the next character, which then has no special meaning.
        if (index + 1 < pattern.length) {
          out.write(RegExp.escape(pattern[index + 1]));
          index += 2;
        } else {
          out.write(RegExp.escape(char));
          index++;
        }
      default:
        out.write(RegExp.escape(char));
        index++;
    }
  }

  return out.toString();
}

class _CharClass {
  const _CharClass(this.regex, this.end);

  final String regex;
  final int end;
}

/// Reads a `[...]` class starting at [start], or null when it never closes.
_CharClass? _readClass(String pattern, int start) {
  var index = start + 1;
  final body = StringBuffer();

  var negated = false;
  if (index < pattern.length && (pattern[index] == '!' || pattern[index] == '^')) {
    negated = true;
    index++;
  }
  // A `]` immediately after the opening (or the negation) is a literal.
  if (index < pattern.length && pattern[index] == ']') {
    body.write(r'\]');
    index++;
  }

  while (index < pattern.length && pattern[index] != ']') {
    final char = pattern[index];
    // Ranges pass through; everything else is escaped so a `.` or `$` inside
    // a class cannot leak regex meaning.
    if (char == '-' &&
        body.isNotEmpty &&
        index + 1 < pattern.length &&
        pattern[index + 1] != ']') {
      body.write('-');
    } else {
      body.write(RegExp.escape(char));
    }
    index++;
  }

  if (index >= pattern.length) return null;
  return _CharClass('[${negated ? '^' : ''}$body]', index + 1);
}
