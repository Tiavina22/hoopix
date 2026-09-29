import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Re-registering every app and extension (`lsregister -r`) makes a running
/// Network Extension VPN (Shadowrocket, Karing) read as reinstalled, so its
/// tunnel drops, and Siri re-indexes every app for minutes. Mole removed
/// its optimize rebuild and narrowed the post-uninstall refresh to `-gc`
/// for this reason; this keeps any new call site from bringing it back.
void main() {
  test('no code that runs lsregister passes it -r', () {
    final callers = <File>[
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            _code(entity).contains('lsregister'))
          entity,
    ];

    // The uninstall path must keep running lsregister (-u, then -gc); an
    // empty caller list would mean this guard no longer checks anything.
    expect(callers, isNotEmpty);
    for (final file in callers) {
      expect(
        _code(file).contains("'-r'"),
        isFalse,
        reason: '${file.path} passes -r to lsregister',
      );
    }
  });
}

/// The file's source with `//` comments dropped, so prose that explains
/// why `-r` is refused cannot trip or satisfy the guard.
String _code(File file) => [
  for (final line in file.readAsLinesSync())
    if (!line.trimLeft().startsWith('//')) line,
].join('\n');
