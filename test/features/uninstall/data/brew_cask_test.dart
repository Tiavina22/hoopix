import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/brew_cask.dart';

const _brew = '/opt/homebrew/bin/brew';
const _env = [
  'HOMEBREW_NO_ENV_HINTS=1',
  'HOMEBREW_NO_AUTO_UPDATE=1',
  'NONINTERACTIVE=1',
];

/// Stands in for `/usr/bin/env ... brew <args>`: checks the environment
/// prefix, records the brew arguments, and answers from [responses] keyed
/// by those arguments. Unlisted commands fail, like an unknown subcommand.
class _FakeBrew extends ProcessRunner {
  _FakeBrew({this.responses = const {}, this.timeOut = const {}});

  final Map<String, ProcessResult> responses;
  final Set<String> timeOut;
  final calls = <String>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    expect(executable, '/usr/bin/env');
    expect(arguments.sublist(0, _env.length), _env);
    expect(arguments[_env.length], _brew);
    final key = arguments.sublist(_env.length + 1).join(' ');
    calls.add(key);
    if (timeOut.contains(key)) {
      return ProcessResult.failure(
        ProcessFailure.timedOut('/usr/bin/env', const Duration(seconds: 10)),
      );
    }
    return responses[key] ??
        ProcessResult.failure(
          ProcessFailure.nonZeroExit('/usr/bin/env', 1, 'Error: $key'),
        );
  }
}

void main() {
  const app = '/Applications/Visual Studio Code.app';
  const vscodeInfo =
      '==> visual-studio-code\n==> Artifacts\nVisual Studio Code.app (App)\n';

  BrewCask brewCaskWith(
    _FakeBrew brew, {
    Set<String> existing = const {_brew, app},
    Map<String, FileSystemEntityType> types = const {},
    String? Function(String)? resolvePath,
    String? Function(String)? readLink,
    Map<String, List<String>> tree = const {},
    List<Duration>? uninstallTimeouts,
  }) => BrewCask(
    probe: brew,
    uninstallRunner: (timeout) {
      uninstallTimeouts?.add(timeout);
      return brew;
    },
    typeOf: (path) =>
        types[path] ??
        (existing.contains(path)
            ? FileSystemEntityType.directory
            : FileSystemEntityType.notFound),
    resolvePath: resolvePath ?? (path) => path,
    readLink: readLink ?? (_) => null,
    listNames: (dir) => tree[dir] ?? const [],
  );

  group('detect', () {
    test(
      'without a brew binary nothing is Homebrew\'s, and nothing runs',
      () async {
        final brew = _FakeBrew();
        final detection = await brewCaskWith(brew, existing: {app}).detect(app);

        expect(detection.kind, CaskDetectionKind.none);
        expect(brew.calls, isEmpty);
      },
    );

    test('stage 1: a path that resolves into a Caskroom', () async {
      final brew = _FakeBrew();
      final detection = await brewCaskWith(
        brew,
        resolvePath: (_) =>
            '/opt/homebrew/Caskroom/visual-studio-code/1.2/Visual Studio Code.app',
      ).detect(app);

      expect(detection.token, 'visual-studio-code');
      expect(brew.calls, isEmpty);
    });

    test('stage 1 ignores a resolved path with another bundle name', () async {
      final brew = _FakeBrew(
        responses: {'list --cask': ProcessResult.success('')},
      );
      final detection = await brewCaskWith(
        brew,
        resolvePath: (_) => '/opt/homebrew/Caskroom/other/1/Other.app',
      ).detect(app);

      expect(detection.kind, CaskDetectionKind.none);
    });

    test('stage 2: exactly one Caskroom token, confirmed by brew', () async {
      final brew = _FakeBrew(
        responses: {
          'list --cask': ProcessResult.success('visual-studio-code\n'),
          'info --cask visual-studio-code': ProcessResult.success(vscodeInfo),
        },
      );
      final detection = await brewCaskWith(
        brew,
        tree: {
          '/opt/homebrew/Caskroom': ['visual-studio-code'],
          '/opt/homebrew/Caskroom/visual-studio-code': ['1.2'],
          '/opt/homebrew/Caskroom/visual-studio-code/1.2': [
            'Visual Studio Code.app',
          ],
        },
      ).detect(app);

      expect(detection.token, 'visual-studio-code');
    });

    test('stage 2 never trusts a name two tokens share', () async {
      final brew = _FakeBrew(
        responses: {'list --cask': ProcessResult.success('a\nb\n')},
      );
      final detection = await brewCaskWith(
        brew,
        tree: {
          '/opt/homebrew/Caskroom': ['a', 'b'],
          '/opt/homebrew/Caskroom/a': ['1'],
          '/opt/homebrew/Caskroom/a/1': ['Visual Studio Code.app'],
          '/opt/homebrew/Caskroom/b': ['1'],
          '/opt/homebrew/Caskroom/b/1': ['Visual Studio Code.app'],
        },
      ).detect(app);

      expect(detection.kind, CaskDetectionKind.none);
      expect(brew.calls.where((c) => c.startsWith('info')), isEmpty);
    });

    test('stage 2 needs brew info to own this very app', () async {
      final brew = _FakeBrew(
        responses: {
          'list --cask': ProcessResult.success('visual-studio-code\n'),
          'info --cask visual-studio-code': ProcessResult.success(
            'Something Else.app (App)',
          ),
        },
      );
      final detection = await brewCaskWith(
        brew,
        tree: {
          '/opt/homebrew/Caskroom': ['visual-studio-code'],
          '/opt/homebrew/Caskroom/visual-studio-code': ['1.2'],
          '/opt/homebrew/Caskroom/visual-studio-code/1.2': [
            'Visual Studio Code.app',
          ],
        },
      ).detect(app);

      expect(detection.kind, CaskDetectionKind.none);
    });

    test('stage 3: a symlink straight into a Caskroom', () async {
      final brew = _FakeBrew();
      final detection = await brewCaskWith(
        brew,
        types: {app: FileSystemEntityType.link},
        resolvePath: (_) => null,
        readLink: (_) =>
            '/usr/local/Caskroom/visual-studio-code/1/Visual Studio Code.app',
      ).detect(app);

      expect(detection.token, 'visual-studio-code');
    });

    test('stage 4: a cask named after the app, confirmed by info', () async {
      const firefox = '/Applications/Firefox.app';
      final brew = _FakeBrew(
        responses: {
          'list --cask': ProcessResult.success('firefox\n'),
          'info --cask firefox': ProcessResult.success('Firefox.app (App)'),
        },
      );
      final detection = await brewCaskWith(
        brew,
        existing: {_brew, firefox},
      ).detect(firefox);

      expect(detection.token, 'firefox');
    });

    test('a list brew cannot produce is unknown, not "not Homebrew"', () async {
      final detection = await brewCaskWith(_FakeBrew()).detect(app);

      expect(detection.kind, CaskDetectionKind.unknown);
    });

    test('a list that times out is reported as such', () async {
      final detection = await brewCaskWith(
        _FakeBrew(timeOut: {'list --cask'}),
      ).detect(app);

      expect(detection.kind, CaskDetectionKind.timedOut);
    });

    test('detectAll asks brew for the cask list once', () async {
      const other = '/Applications/Other.app';
      final brew = _FakeBrew(
        responses: {'list --cask': ProcessResult.success('firefox\n')},
      );
      final detections = await brewCaskWith(
        brew,
        existing: {_brew, app, other},
      ).detectAll([app, other]);

      expect(detections.values.map((d) => d.kind), [
        CaskDetectionKind.none,
        CaskDetectionKind.none,
      ]);
      expect(brew.calls, ['list --cask']);
    });
  });

  group('uninstall', () {
    test('zaps, then confirms the cask and the app are both gone', () async {
      final brew = _FakeBrew(
        responses: {
          'uninstall --cask --zap visual-studio-code': ProcessResult.success(
            '',
          ),
          'list --cask': ProcessResult.success('firefox\n'),
        },
      );
      final result = await brewCaskWith(
        brew,
        existing: {_brew},
      ).uninstall('visual-studio-code', appPath: app, zap: true);

      expect(result, CaskUninstallResult.removed);
      expect(brew.calls, [
        'uninstall --cask --zap visual-studio-code',
        'list --cask',
      ]);
    });

    test('a guarded app is uninstalled without --zap', () async {
      final brew = _FakeBrew(
        responses: {
          'uninstall --cask visual-studio-code': ProcessResult.success(''),
          'list --cask': ProcessResult.success(''),
        },
      );
      await brewCaskWith(
        brew,
        existing: {_brew},
      ).uninstall('visual-studio-code', appPath: app, zap: false);

      expect(brew.calls.first, 'uninstall --cask visual-studio-code');
    });

    test('is not removed while brew still lists the cask', () async {
      final brew = _FakeBrew(
        responses: {
          'uninstall --cask --zap visual-studio-code': ProcessResult.success(
            '',
          ),
          'list --cask': ProcessResult.success('visual-studio-code\n'),
        },
      );
      final result = await brewCaskWith(
        brew,
        existing: {_brew},
      ).uninstall('visual-studio-code', appPath: app, zap: true);

      expect(result, CaskUninstallResult.failed);
    });

    test('is not removed while the app bundle is still on disk', () async {
      final brew = _FakeBrew(
        responses: {
          'uninstall --cask --zap visual-studio-code': ProcessResult.success(
            '',
          ),
          'list --cask': ProcessResult.success(''),
        },
      );
      final result = await brewCaskWith(
        brew,
      ).uninstall('visual-studio-code', appPath: app, zap: true);

      expect(result, CaskUninstallResult.failed);
    });

    test('a timeout is never followed by verification', () async {
      final brew = _FakeBrew(
        timeOut: {'uninstall --cask --zap visual-studio-code'},
      );
      final result = await brewCaskWith(
        brew,
      ).uninstall('visual-studio-code', appPath: app, zap: true);

      expect(result, CaskUninstallResult.timedOut);
      expect(brew.calls, ['uninstall --cask --zap visual-studio-code']);
    });

    test('gives a large app more time, as Mole does', () async {
      final brew = _FakeBrew();
      final timeouts = <Duration>[];
      final cask = brewCaskWith(brew, uninstallTimeouts: timeouts);
      const gib = 1 << 30;

      for (final size in [null, 6 * gib, 16 * gib]) {
        await cask.uninstall('x', appPath: app, zap: true, sizeBytes: size);
      }

      expect(timeouts, const [
        Duration(minutes: 5),
        Duration(minutes: 10),
        Duration(minutes: 15),
      ]);
    });
  });

  test('installState reads brew list --cask', () async {
    final installed = _FakeBrew(
      responses: {'list --cask': ProcessResult.success('firefox\n')},
    );
    expect(
      await brewCaskWith(installed).installState('firefox'),
      CaskInstallState.installed,
    );
    expect(
      await brewCaskWith(installed).installState('zoom'),
      CaskInstallState.notInstalled,
    );
    expect(
      await brewCaskWith(_FakeBrew()).installState('firefox'),
      CaskInstallState.unknown,
    );
    expect(
      await brewCaskWith(
        _FakeBrew(timeOut: {'list --cask'}),
      ).installState('firefox'),
      CaskInstallState.timedOut,
    );
  });
}
