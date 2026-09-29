import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/domain/entities/cache_owner_attribution.dart';

/// Cases ported from Mole's `tests/core_safe_functions.bats` "cache owner
/// probe" tests (#1390), with the same process lines.
const _home = '/Users/tester';

/// `ps -axo pid,ppid,comm,args`: a header, then `pid ppid comm args`, where
/// comm is the executable path cut to 16 characters, as ps prints it.
String table(List<String> commandLines, {int ppid = 1}) {
  final rows = <String>['  PID  PPID COMM             ARGS'];
  var pid = 700;
  for (final args in commandLines) {
    final executable = args.startsWith('/')
        ? args
        : '/usr/bin/${args.split(' ').first}';
    final comm = executable.length > 16
        ? executable.substring(0, 16)
        : executable.padRight(16);
    rows.add('  ${pid++}  $ppid $comm $args');
  }
  return rows.join('\n');
}

Future<bool> ownerRunning(
  String owner, {
  required String processes,
  String executables = '',
  int selfPid = 99999,
  Map<String, String?> bundles = const {},
}) {
  final parsed = ProcessTable.parse(
    table: processes,
    executables: executables,
    selfPid: selfPid,
  )!;
  return CacheOwnerAttribution(
    table: parsed,
    home: _home,
    bundleIdOf: (bundle) async => bundles[bundle],
    isDirectory: bundles.containsKey,
  ).isOwnerRunning(owner);
}

void main() {
  test('requires corroboration for a shared leaf name', () async {
    final processes = table([
      '/Applications/Claude.app/Contents/Frameworks/Squirrel.framework/'
          'Resources/ShipIt /Applications/Claude.app/Contents/Frameworks/'
          'Squirrel.framework/Resources/ShipIt '
          'com.anthropic.claudefordesktop.ShipIt',
      '/System/Library/PrivateFrameworks/DataAccess.framework/Support/'
          'dataaccessd',
      '/usr/libexec/syncdefaultsd',
    ]);

    // VS Code's ShipIt cache is not busy because Claude's ShipIt runs, and
    // "data" is not read out of dataaccessd.
    expect(
      await ownerRunning('com.microsoft.VSCode.ShipIt', processes: processes),
      isFalse,
    );
    expect(
      await ownerRunning(
        'com.plausiblelabs.crashreporter.data',
        processes: processes,
      ),
      isFalse,
    );
    expect(
      await ownerRunning(
        'com.anthropic.claudefordesktop.ShipIt',
        processes: processes,
      ),
      isTrue,
    );
  });

  test('still catches a corroborated helper (AcCoreConsole)', () async {
    expect(
      await ownerRunning(
        'com.autodesk.AcCoreConsole',
        processes: table([
          '/Applications/Autodesk Fusion.app/Contents/MacOS/AcCoreConsole',
        ]),
      ),
      isTrue,
    );
  });

  group("attributes an app bundle's lines by its identifier", () {
    const apps = '$_home/Applications';
    const bundles = {
      '$apps/Brave Browser Nightly.app': 'com.brave.Browser.nightly',
      '$apps/Browsers/Brave Origin Nightly.app':
          'com.brave.Browser.origin.nightly',
      '$apps/Karabiner-Elements.app': 'org.pqrs.Karabiner-Elements',
      '$apps/Karabiner-Elements.app/Contents/Resources/'
              'Karabiner-Elements Settings.app':
          'org.pqrs.Karabiner-Elements.Settings',
      '/Applications/Unrelated.app': 'com.example.unrelated',
    };
    const origin =
        '$apps/Browsers/Brave Origin Nightly.app/Contents/MacOS/'
        'Brave Origin Nightly';
    const originHelper =
        '$apps/Browsers/Brave Origin Nightly.app/Contents/Frameworks/'
        'Brave Origin Nightly Framework.framework/Versions/154.1.98.11/'
        'Helpers/Brave Origin Nightly Helper (Renderer).app/Contents/MacOS/'
        'Brave Origin Nightly Helper (Renderer)';
    const nightly =
        '$apps/Brave Browser Nightly.app/Contents/MacOS/Brave Browser Nightly';

    Future<bool> probe(String owner, List<String> lines) =>
        ownerRunning(owner, processes: table(lines), bundles: bundles);

    test('a sibling channel does not keep the other busy', () async {
      final lines = [origin, '$originHelper --type=renderer'];
      expect(await probe('com.brave.Browser.nightly', lines), isFalse);
      expect(await probe('com.brave.Browser.origin.nightly', lines), isTrue);
    });

    test("the owner's own bundle counts", () async {
      expect(
        await probe('com.brave.Browser.nightly', [origin, nightly]),
        isTrue,
      );
    });

    test('a later argument naming another app does not decide', () async {
      expect(
        await probe('com.brave.Browser.nightly', [
          '$nightly /Applications/Unrelated.app/Contents/MacOS/Unrelated',
        ]),
        isTrue,
      );
    });

    test('a nested app extending the owner id counts', () async {
      expect(
        await probe('org.pqrs.Karabiner-Elements.Settings', [
          '$apps/Karabiner-Elements.app/Contents/Resources/'
              'Karabiner-Elements Settings.app/Contents/MacOS/'
              'Karabiner-Elements Settings',
        ]),
        isTrue,
      );
    });

    test('an unreadable bundle keeps the line busy', () async {
      expect(
        await ownerRunning(
          'com.brave.Browser.nightly',
          processes: table([
            '$apps/Broken.app/Contents/MacOS/Brave Nightly Beta',
          ]),
          // The bundle exists; its identifier cannot be read.
          bundles: {...bundles, '$apps/Broken.app': null},
        ),
        isTrue,
      );
    });

    test('a line outside the application roots keeps its tokens', () async {
      expect(
        await probe('com.brave.Browser.origin.nightly', [
          '/opt/BraveNightly --label Brave --channel Nightly --open '
              '$apps/Brave Browser Nightly.app/Contents/MacOS/Other',
        ]),
        isTrue,
      );
    });
  });

  group('attributes a rewritten argv by the executable ps reports', () {
    const apps = '$_home/Applications';
    const bundles = {
      '$apps/Brave Browser Nightly.app': 'com.brave.Browser.nightly',
      '$apps/Brave Origin Nightly.app': 'com.brave.Browser.origin.nightly',
      '$apps/Autodesk Fusion.app': 'com.autodesk.fusion360',
    };
    const originHelper =
        '$apps/Brave Origin Nightly.app/Contents/MacOS/'
        'Brave Origin Nightly Helper';
    const nightly =
        '$apps/Brave Browser Nightly.app/Contents/MacOS/Brave Browser Nightly';
    const console = '$apps/Autodesk Fusion.app/Contents/MacOS/AcCoreConsole';

    String rewritten(String executable, String args) =>
        '  PID  PPID COMM ARGS\n  801     1 ${executable.substring(0, 16)} '
        '$args';

    test('the executable path places a line argv no longer names', () async {
      final processes = rewritten(
        originHelper,
        'Brave Origin Nightly Helper --type=renderer',
      );
      expect(
        await ownerRunning(
          'com.brave.Browser.nightly',
          processes: processes,
          executables: '  801 $originHelper',
          bundles: bundles,
        ),
        isFalse,
      );
      // Without the executable read, the line cannot be placed: busy.
      expect(
        await ownerRunning(
          'com.brave.Browser.nightly',
          processes: processes,
          bundles: bundles,
        ),
        isTrue,
      );
    });

    test("the owner's and its helper's own executables count", () async {
      expect(
        await ownerRunning(
          'com.brave.Browser.nightly',
          processes: rewritten(nightly, 'Brave Browser Nightly --restore'),
          executables: '  801 $nightly',
          bundles: bundles,
        ),
        isTrue,
      );
      expect(
        await ownerRunning(
          'com.autodesk.AcCoreConsole',
          processes: rewritten(console, 'AcCoreConsole --vendor autodesk'),
          executables: '  801 $console',
          bundles: bundles,
        ),
        isTrue,
      );
    });
  });

  test("ignores hoopix's own measurement processes and bundle id", () async {
    final processes = table([
      'du -skPx $_home/Library/Caches/com.example.SampleApp',
      '/Applications/hoopix.app/Contents/MacOS/hoopix '
          '--bundle com.lyrify.hoopix com.example.SampleApp',
    ]);

    expect(
      await ownerRunning('com.example.SampleApp', processes: processes),
      isFalse,
    );
  });

  test("drops hoopix's own process tree, ancestors and descendants", () async {
    const processes =
        '  PID  PPID COMM ARGS\n'
        '  500     1 /bin/zsh /bin/zsh -c open com.example.SampleApp\n'
        '  600   500 /Applications/h /Applications/hoopix.app/Contents/MacOS/hoopix\n'
        '  700   600 /usr/sbin/lsof lsof +D /x/com.example.SampleApp\n'
        '  800   700 /bin/cat cat com.example.SampleApp';

    expect(
      await ownerRunning(
        'com.example.SampleApp',
        processes: processes,
        selfPid: 600,
      ),
      isFalse,
    );
    expect(
      await ownerRunning(
        'com.example.SampleApp',
        processes: processes,
        selfPid: 123,
      ),
      isTrue,
    );
  });

  test('an unreadable process table yields no snapshot at all', () {
    expect(ProcessTable.parse(table: '', executables: '', selfPid: 1), isNull);
    expect(
      ProcessTable.parse(
        table: '  PID  PPID COMM ARGS',
        executables: '',
        selfPid: 1,
      ),
      isNull,
    );
  });
}
