import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/history/data/datasources/operation_log_reader.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_history_reader_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  String line(String path, {String outcome = 'trashed'}) =>
      '{"at":"2026-01-01T00:00:00.000","command":"uninstall",'
      '"outcome":"$outcome","path":"$path"}';

  Future<File> writeLog(String content) async {
    final file = File('${home.path}/operations.log');
    await file.writeAsString(content);
    return file;
  }

  const reader = OperationLogReader();

  test('reads every line, newest last-written first', () async {
    final file = await writeLog(
      '${line('/A')}\n${line('/B')}\n${line('/C')}\n',
    );

    final entries = await reader.readRecent(file.path, limit: 10);

    expect(entries.map((e) => e.path), ['/C', '/B', '/A']);
  });

  test('stops at the requested limit without reading the rest', () async {
    final file = await writeLog(
      '${line('/A')}\n${line('/B')}\n${line('/C')}\n',
    );

    final entries = await reader.readRecent(file.path, limit: 2);

    expect(entries.map((e) => e.path), ['/C', '/B']);
  });

  test('a limit of zero reads nothing', () async {
    final file = await writeLog(line('/A'));

    expect(await reader.readRecent(file.path, limit: 0), isEmpty);
  });

  test('a missing file is an empty list, not an error', () async {
    final entries = await reader.readRecent(
      '${home.path}/does-not-exist.log',
      limit: 10,
    );

    expect(entries, isEmpty);
  });

  test('an empty file is an empty list', () async {
    final file = await writeLog('');

    expect(await reader.readRecent(file.path, limit: 10), isEmpty);
  });

  test('the last line survives without a trailing newline', () async {
    final file = await writeLog('${line('/A')}\n${line('/B')}');

    final entries = await reader.readRecent(file.path, limit: 10);

    expect(entries.map((e) => e.path), ['/B', '/A']);
  });

  test(
    'reads across a chunk boundary without losing or duplicating lines',
    () async {
      // One 64KB chunk is not enough to hold this file in a single backward
      // read, so the boundary itself has to be exercised.
      final buffer = StringBuffer();
      for (var i = 0; i < 3000; i++) {
        buffer.write(line('/app-$i.app'));
        buffer.write('\n');
      }
      final file = await writeLog(buffer.toString());

      final entries = await reader.readRecent(file.path, limit: 3000);

      expect(entries.length, 3000);
      expect(entries.first.path, '/app-2999.app');
      expect(entries.last.path, '/app-0.app');
      // No duplicate across the chunk seam and no entry dropped.
      expect(entries.map((e) => e.path).toSet().length, 3000);
    },
  );

  test('a blank line never costs a slot of the limit', () async {
    final file = await writeLog('${line('/A')}\n\n${line('/B')}\n');

    final entries = await reader.readRecent(file.path, limit: 2);

    expect(entries.map((e) => e.path), ['/B', '/A']);
  });

  test('an extra trailing blank line is not a spurious entry', () async {
    final file = await writeLog('${line('/A')}\n\n');

    final entries = await reader.readRecent(file.path, limit: 10);

    expect(entries.map((e) => e.path), ['/A']);
  });

  test(
    'a line that is not the expected JSON shape is skipped, not fatal',
    () async {
      final file = await writeLog(
        '${line('/A')}\nnot json at all\n{"unexpected":"shape"}\n${line('/B')}\n',
      );

      final entries = await reader.readRecent(file.path, limit: 10);

      expect(entries.map((e) => e.path), ['/B', '/A']);
    },
  );

  test('parses detail and sizeBytes when present, null when absent', () async {
    final file = await writeLog(
      '{"at":"2026-01-01T00:00:00.000","command":"uninstall",'
      '"outcome":"refused","path":"/CapCut.app","detail":"denied",'
      '"sizeBytes":1024}\n'
      '${line('/NoDetail.app')}\n',
    );

    final entries = await reader.readRecent(file.path, limit: 10);

    expect(entries[0].detail, isNull);
    expect(entries[0].sizeBytes, isNull);
    expect(entries[1].detail, 'denied');
    expect(entries[1].sizeBytes, 1024);
  });

  test('malformed UTF-8 in a path becomes the replacement character', () async {
    final file = File('${home.path}/operations.log');
    await file.writeAsBytes([
      ...'{"at":"2026-01-01T00:00:00.000","command":"uninstall","outcome":"trashed","path":"/caf'
          .codeUnits,
      0xE9, // a lone Latin-1 'é', not valid UTF-8 on its own
      ...'.app"}\n'.codeUnits,
    ]);

    final entries = await reader.readRecent(file.path, limit: 10);

    expect(entries.single.path, '/caf�.app');
  });
}
