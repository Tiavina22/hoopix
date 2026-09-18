import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/removal_warnings.dart';

/// `id -u` answers [uid]; `launchctl print` succeeds for [loaded] labels and
/// exits 113, as launchd does, for anything else.
class _Launchd extends ProcessRunner {
  _Launchd({this.uid = '501', this.loaded = const {}});

  final String? uid;
  final Set<String> loaded;
  final calls = <String>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final key = [executable, ...arguments].join(' ');
    calls.add(key);
    if (key == 'id -u') {
      return uid == null
          ? ProcessResult.failure(ProcessFailure.nonZeroExit('id', 1, ''))
          : ProcessResult.success('$uid\n');
    }
    final label = arguments.last.split('/').last;
    return loaded.contains(label) && arguments.last == 'gui/$uid/$label'
        ? ProcessResult.success('')
        : ProcessResult.failure(
            ProcessFailure.nonZeroExit(executable, 113, 'Could not find'),
          );
  }
}

void main() {
  group('backgroundJobLoaded', () {
    test('is true when any label is loaded in the gui domain', () async {
      final launchd = _Launchd(loaded: {'com.example.MyApp.Helper'});

      expect(
        await RemovalWarnings(runner: launchd).backgroundJobLoaded([
          'com.example.MyApp',
          'com.example.MyApp.Helper',
        ]),
        isTrue,
      );
      expect(launchd.calls, [
        'id -u',
        'launchctl print gui/501/com.example.MyApp',
        'launchctl print gui/501/com.example.MyApp.Helper',
      ]);
    });

    test('is false when nothing is loaded', () async {
      expect(
        await RemovalWarnings(
          runner: _Launchd(),
        ).backgroundJobLoaded(['com.example.MyApp']),
        isFalse,
      );
    });

    test('never probes a demoted or malformed label', () async {
      final launchd = _Launchd(loaded: {'unknown'});

      expect(
        await RemovalWarnings(
          runner: launchd,
        ).backgroundJobLoaded(['unknown', 'not an id', '']),
        isFalse,
      );
      expect(launchd.calls, isEmpty);
    });

    test('says nothing when the uid cannot be read', () async {
      expect(
        await RemovalWarnings(
          runner: _Launchd(uid: null, loaded: {'com.example.MyApp'}),
        ).backgroundJobLoaded(['com.example.MyApp']),
        isFalse,
      );
    });
  });

  group('hasSystemExtension', () {
    RemovalWarnings warningsOver(Map<String, List<String>> tree) =>
        RemovalWarnings(listNames: (dir) => tree[dir] ?? const []);

    test('finds an extension one team folder down, at a . boundary', () {
      final warnings = warningsOver({
        '/Library/SystemExtensions': ['C131C535'],
        '/Library/SystemExtensions/C131C535': [
          'com.adguard.mac.adguard.network-extension.systemextension',
        ],
      });

      expect(warnings.hasSystemExtension('com.adguard.mac.adguard'), isTrue);
    });

    test('never matches past a non-dot boundary or a vendor prefix', () {
      final warnings = warningsOver({
        '/Library/SystemExtensions': ['X'],
        '/Library/SystemExtensions/X': [
          'com.adguard.mac.adguardvpn.systemextension',
          'com.adguard.mac.systemextension',
        ],
      });

      expect(warnings.hasSystemExtension('com.adguard.mac.adguard'), isFalse);
    });

    test('ignores anything that is not a .systemextension', () {
      final warnings = warningsOver({
        '/Library/SystemExtensions': ['X'],
        '/Library/SystemExtensions/X': ['com.example.MyApp.helper'],
      });

      expect(warnings.hasSystemExtension('com.example.MyApp'), isFalse);
    });

    test('a demoted bundle id has no extension', () {
      final warnings = warningsOver({
        '/Library/SystemExtensions': ['unknown.systemextension'],
      });

      expect(warnings.hasSystemExtension('unknown'), isFalse);
    });
  });
}
