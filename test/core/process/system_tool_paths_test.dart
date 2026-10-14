import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';

void main() {
  test('every system tool resolves to a file macOS ships at that path', () {
    for (final entry in systemToolPaths.entries) {
      expect(
        FileSystemEntity.typeSync(entry.value),
        FileSystemEntityType.file,
        reason: '${entry.key} -> ${entry.value}',
      );
    }
  });

  test('a system tool runs by absolute path, a user tool by name', () {
    expect(resolveExecutable('lsof'), '/usr/sbin/lsof');
    expect(resolveExecutable('ps'), '/bin/ps');
    expect(resolveExecutable('npm'), 'npm');
    expect(
      resolveExecutable('/opt/homebrew/bin/brew'),
      '/opt/homebrew/bin/brew',
    );
  });

  test('every safety probe hoopix relies on is pinned', () {
    for (final tool in [
      'lsof',
      'ps',
      'pgrep',
      'pkill',
      'stat',
      'plutil',
      'sqlite3',
      'launchctl',
      'osascript',
      'mdfind',
      'pkgutil',
      'getconf',
    ]) {
      expect(systemToolPaths, contains(tool), reason: tool);
    }
  });

  test('a stand-in earlier on PATH is never the one that runs', () async {
    final fakeBin = await Directory.systemTemp.createTemp('hoopix_fake_bin_');
    addTearDown(() => fakeBin.delete(recursive: true));
    final fake = File('${fakeBin.path}/id');
    await fake.writeAsString('#!/bin/sh\necho hijacked\n');
    await Process.run('/bin/chmod', ['+x', fake.path]);
    // What a terminal-launched hoopix can inherit: a user folder first.
    final hijackedPath = {'PATH': '${fakeBin.path}:/usr/bin:/bin'};

    final byName = await Process.run('id', ['-u'], environment: hijackedPath);
    expect('${byName.stdout}'.trim(), 'hijacked');

    final byPath = await Process.run(resolveExecutable('id'), [
      '-u',
    ], environment: hijackedPath);
    expect(int.tryParse('${byPath.stdout}'.trim()), isNotNull);
  });
}
