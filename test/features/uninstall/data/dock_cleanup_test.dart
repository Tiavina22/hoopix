import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/dock_cleanup.dart';

const _home = '/Users/tester';
const _plist = '$_home/Library/Preferences/com.apple.dock.plist';

Map<String, String> _tile(String path, {String? bundleId}) => {
  'tile-type': 'file-tile',
  'tile-data:file-data:_CFURLString': Uri.file('$path/').toString(),
  'tile-data:bundle-identifier': ?bundleId,
};

/// An in-memory Dock plist behind a fake PlistBuddy: `Print` answers from
/// the arrays, `Delete` really removes the entry so later indices shift,
/// the way the real plist does.
class _FakeDock extends ProcessRunner {
  _FakeDock(this.arrays);

  final Map<String, List<Map<String, String>>> arrays;
  var dockRestarts = 0;
  var calls = 0;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls++;
    if (executable == 'killall') {
      expect(arguments, ['Dock']);
      dockRestarts++;
      return ProcessResult.success('');
    }
    expect(executable, '/usr/libexec/PlistBuddy');
    expect(arguments.last, _plist);
    final command = arguments[1];
    final space = command.indexOf(' ');
    final verb = command.substring(0, space);
    final parts = command.substring(space + 2).split(':');
    final tiles = arrays[parts[0]] ?? const [];
    final index = int.parse(parts[1]);
    if (index >= tiles.length) return _missing(command);
    if (verb == 'Delete') {
      arrays[parts[0]]!.removeAt(index);
      return ProcessResult.success('');
    }
    final value = tiles[index][parts.sublist(2).join(':')];
    return value == null
        ? _missing(command)
        : ProcessResult.success('$value\n');
  }

  ProcessResult _missing(String command) => ProcessResult.failure(
    ProcessFailure.nonZeroExit('PlistBuddy', 1, 'Does Not Exist: $command'),
  );

  List<String> urls(String array) => [
    for (final tile in arrays[array]!)
      tile['tile-data:file-data:_CFURLString']!,
  ];
}

void main() {
  DockCleanup cleanupWith(_FakeDock dock, {bool plistExists = true}) =>
      DockCleanup(
        home: _home,
        runner: dock,
        typeOf: (path) => path == _plist && !plistExists
            ? FileSystemEntityType.notFound
            : FileSystemEntityType.file,
      );

  test(
    'removes the tile whose URL is exactly the app, spaces and all',
    () async {
      final dock = _FakeDock({
        'persistent-apps': [
          _tile('/System/Applications/Mail.app'),
          _tile('/Applications/Visual Studio Code.app'),
          _tile('/Applications/Zed.app'),
        ],
      });

      final changed = await cleanupWith(dock).remove(const [
        DockTarget(
          appPath: '/Applications/Visual Studio Code.app',
          bundleId: 'unknown',
        ),
      ]);

      expect(changed, isTrue);
      expect(dock.urls('persistent-apps'), [
        'file:///System/Applications/Mail.app/',
        'file:///Applications/Zed.app/',
      ]);
      expect(dock.dockRestarts, 1);
    },
  );

  test(
    "never takes the other install's tile, which Mole's substring match would",
    () async {
      final dock = _FakeDock({
        'persistent-apps': [_tile('/Users/tester/Applications/Foo.app')],
      });

      final changed = await cleanupWith(dock).remove(const [
        DockTarget(appPath: '/Applications/Foo.app', bundleId: 'unknown'),
      ]);

      expect(changed, isFalse);
      expect(dock.arrays['persistent-apps'], hasLength(1));
      expect(dock.dockRestarts, 0);
    },
  );

  test('matches by bundle id, and removes back-to-back tiles', () async {
    final dock = _FakeDock({
      'persistent-apps': [
        _tile('/Applications/Old/Foo.app', bundleId: 'com.example.foo'),
        _tile('/Applications/Foo.app', bundleId: 'com.example.foo'),
        _tile('/Applications/Bar.app', bundleId: 'com.example.bar'),
      ],
      'recent-apps': [
        _tile('/Applications/Foo.app', bundleId: 'com.example.foo'),
      ],
    });

    await cleanupWith(dock).remove(const [
      DockTarget(appPath: '/Applications/Foo.app', bundleId: 'com.example.foo'),
    ]);

    expect(dock.urls('persistent-apps'), ['file:///Applications/Bar.app/']);
    expect(dock.arrays['recent-apps'], isEmpty);
  });

  test('a demoted bundle id never matches a tile by bundle id', () async {
    final dock = _FakeDock({
      'persistent-apps': [
        _tile('/Applications/Foo Beta.app', bundleId: 'com.example.foo'),
        _tile('/Applications/Odd.app', bundleId: 'unknown'),
      ],
    });

    final changed = await cleanupWith(dock).remove(const [
      DockTarget(appPath: '/Applications/Foo.app', bundleId: 'unknown'),
    ]);

    expect(changed, isFalse);
    expect(dock.arrays['persistent-apps'], hasLength(2));
  });

  test('walks the stacks section too', () async {
    final dock = _FakeDock({
      'persistent-others': [_tile('/Applications/Foo.app')],
    });

    await cleanupWith(dock).remove(const [
      DockTarget(appPath: '/Applications/Foo.app', bundleId: 'unknown'),
    ]);

    expect(dock.arrays['persistent-others'], isEmpty);
  });

  test('does nothing at all without a Dock plist', () async {
    final dock = _FakeDock({
      'persistent-apps': [_tile('/Applications/Foo.app')],
    });

    final changed = await cleanupWith(dock, plistExists: false).remove(const [
      DockTarget(appPath: '/Applications/Foo.app', bundleId: 'unknown'),
    ]);

    expect(changed, isFalse);
    expect(dock.calls, 0);
  });

  test('ignores a relative path or one with control characters', () async {
    final dock = _FakeDock({
      'persistent-apps': [_tile('/Applications/Foo.app')],
    });

    await cleanupWith(dock).remove(const [
      DockTarget(appPath: 'Foo.app', bundleId: 'unknown'),
      DockTarget(appPath: '/Applications/Foo\n.app', bundleId: 'unknown'),
    ]);

    expect(dock.calls, 0);
  });
}
