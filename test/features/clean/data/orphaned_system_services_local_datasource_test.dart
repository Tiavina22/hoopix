import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/app_leftovers_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/orphaned_system_services_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _notFound(String value) => ProcessResult.failure(
  ProcessFailure.notFound(value, 'File Does Not Exist'),
);
ProcessResult _mdfindEmpty() => ProcessResult.success('');

void main() {
  late Directory root;
  late Directory daemons;
  late Directory agents;
  late Directory helpers;
  late Directory applications;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hoopix_orphan_services_');
    daemons = Directory('${root.path}/LaunchDaemons')..createSync();
    agents = Directory('${root.path}/LaunchAgents')..createSync();
    helpers = Directory('${root.path}/PrivilegedHelperTools')..createSync();
    applications = Directory('${root.path}/Applications')..createSync();
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Directory fakeRoot(String path) {
    const map = {
      '/Library/LaunchDaemons': 'LaunchDaemons',
      '/Library/LaunchAgents': 'LaunchAgents',
      '/Library/PrivilegedHelperTools': 'PrivilegedHelperTools',
    };
    return map.containsKey(path)
        ? Directory('${root.path}/${map[path]}')
        : Directory(path);
  }

  Future<String> makePlist(
    Directory dir,
    String bundleId, {
    String? programArgs0,
    String? program,
  }) async {
    final path = '${dir.path}/$bundleId.plist';
    await File(path).create(recursive: true);
    return path;
  }

  Future<String> makeHelperFile(String name) async {
    final path = '${helpers.path}/$name';
    await File(path).create(recursive: true);
    return path;
  }

  Map<String, ProcessResult> withProgram(
    String plist, {
    String? programArguments0,
    String? program,
  }) => {
    '/usr/libexec/PlistBuddy -c Print :ProgramArguments:0 $plist':
        programArguments0 != null
        ? ProcessResult.success(programArguments0)
        : _notFound('PlistBuddy'),
    if (programArguments0 == null)
      '/usr/libexec/PlistBuddy -c Print :Program $plist': program != null
          ? ProcessResult.success(program)
          : _notFound('PlistBuddy'),
  };

  OrphanedSystemServicesLocalDataSource source(
    Map<String, ProcessResult> responses,
  ) => OrphanedSystemServicesLocalDataSource(
    home: '${root.path}/home',
    probe: FakeProcessRunner(responses),
    resolver: BundleInstallResolver(
      probe: FakeProcessRunner(responses),
      appRoots: [applications.path],
    ),
    directory: fakeRoot,
  );

  test('section name matches the constant App leftovers uses', () async {
    final result = await source(const {}).enumerate();
    expect(result.section, AppLeftoversLocalDataSource.appLeftovers);
  });

  group('a LaunchDaemon/LaunchAgent plist', () {
    test(
      'is orphaned when its binary is missing and no pattern protects it',
      () async {
        final plist = await makePlist(daemons, 'com.example.orphan');
        final responses = {
          ...withProgram(
            plist,
            programArguments0: '/usr/local/opt/example/bin/example',
          ),
          "mdfind kMDItemCFBundleIdentifier == 'com.example.orphan'":
              _mdfindEmpty(),
        };

        final result = await source(responses).enumerate();

        expect(result.paths, [plist]);
        expect(result.privilegedDeletionPaths, {plist});
        expect(
          result.revalidatorKeys[plist],
          OrphanedSystemServicesLocalDataSource.revalidatorKey,
        );
      },
    );

    test('is kept when the plist has no usable Program key', () async {
      final plist = await makePlist(daemons, 'com.example.nokey');
      final responses = withProgram(plist);

      expect((await source(responses).enumerate()).paths, isEmpty);
    });

    test(
      'is kept when the binary still exists outside PrivilegedHelperTools',
      () async {
        final binary = '${root.path}/opt/example/bin/example';
        await File(binary).create(recursive: true);
        final plist = await makePlist(daemons, 'com.example.alive');
        final responses = withProgram(plist, programArguments0: binary);

        expect((await source(responses).enumerate()).paths, isEmpty);
      },
    );

    test('is kept when the binary is under a package-manager path', () async {
      final plist = await makePlist(daemons, 'com.example.brewed');
      final responses = withProgram(
        plist,
        programArguments0: '/opt/homebrew/bin/example',
      );

      expect((await source(responses).enumerate()).paths, isEmpty);
    });

    test('is kept for a com.apple.* plist regardless of its binary', () async {
      final plist = await makePlist(daemons, 'com.apple.something');
      final responses = withProgram(
        plist,
        programArguments0: '/usr/local/opt/gone/bin/gone',
      );

      expect((await source(responses).enumerate()).paths, isEmpty);
    });

    test('is kept when a standalone helper app Program shape is missing '
        '(updater mid-swap)', () async {
      final plist = await makePlist(daemons, 'com.example.helperapp');
      final responses = withProgram(
        plist,
        programArguments0:
            '/Library/PrivilegedHelperTools/com.example.helperapp.app'
            '/Contents/MacOS/helperapp',
      );

      expect((await source(responses).enumerate()).paths, isEmpty);
    });

    test(
      'is kept when a matching protect pattern finds the app installed',
      () async {
        final plist = await makePlist(daemons, 'com.docker.vmnetd');
        final responses = {
          ...withProgram(
            plist,
            programArguments0: '/usr/local/opt/docker/bin/vmnetd',
          ),
          // The hardcoded /Applications/Docker.app path is checked
          // directly, so an installed-app proof here has to come through
          // the resolver's own (fully injected) fallback instead.
          "mdfind kMDItemCFBundleIdentifier == 'com.docker.vmnetd'":
              ProcessResult.success('/Applications/Docker.app\n'),
        };

        expect((await source(responses).enumerate()).paths, isEmpty);
      },
    );

    test(
      'is orphaned when a matching protect pattern finds the app gone',
      () async {
        final plist = await makePlist(daemons, 'com.docker.vmnetd');
        final responses = {
          ...withProgram(
            plist,
            programArguments0: '/usr/local/opt/docker/bin/vmnetd',
          ),
          "mdfind kMDItemCFBundleIdentifier == 'com.docker.vmnetd'":
              _mdfindEmpty(),
        };

        expect((await source(responses).enumerate()).paths, [plist]);
      },
    );

    test('homebrew.mxcl.* is unconditionally protected', () async {
      final plist = await makePlist(daemons, 'homebrew.mxcl.redis');
      final responses = withProgram(
        plist,
        programArguments0: '/opt/homebrew/opt/redis/bin/redis-server',
      );

      // Package-managed path alone already protects it, but even a
      // non-package binary would be caught by the pattern's empty app list.
      expect((await source(responses).enumerate()).paths, isEmpty);
    });

    test('is orphaned when its binary is a PrivilegedHelperTools file whose '
        'parent app is gone', () async {
      final binary = '/Library/PrivilegedHelperTools/com.example.helper';
      final helperFile = await makeHelperFile('com.example.helper');
      final plist = await makePlist(daemons, 'com.example.service');
      final responses = {
        ...withProgram(plist, programArguments0: binary),
        "mdfind kMDItemCFBundleIdentifier == 'com.example.helper'":
            _mdfindEmpty(),
      };

      // The PrivilegedHelperTools scan independently proposes the same
      // underlying file too — Mole's own two scans overlap the same way.
      expect(
        (await source(responses).enumerate()).paths,
        unorderedEquals([plist, helperFile]),
      );
    });
  });

  group('a PrivilegedHelperTools file', () {
    test('is orphaned when its parent app cannot be found', () async {
      final helper = await makeHelperFile('com.example.helper');
      final responses = {
        "mdfind kMDItemCFBundleIdentifier == 'com.example.helper'":
            _mdfindEmpty(),
      };

      final result = await source(responses).enumerate();

      expect(result.paths, [helper]);
      expect(result.privilegedDeletionPaths, {helper});
    });

    test('is kept for an obvious data file, whatever its name', () async {
      await makeHelperFile('com.example.settings.json');

      expect((await source(const {}).enumerate()).paths, isEmpty);
    });

    test('is kept for a com.apple.* file', () async {
      await makeHelperFile('com.apple.something');

      expect((await source(const {}).enumerate()).paths, isEmpty);
    });

    test('is kept for a name that is not a reverse-DNS bundle id', () async {
      await makeHelperFile('netbird');

      expect((await source(const {}).enumerate()).paths, isEmpty);
    });

    test('is kept when a protect pattern finds the app installed', () async {
      await Directory('${applications.path}/zoom.us.app').create();
      await makeHelperFile('us.zoom.updater');

      expect((await source(const {}).enumerate()).paths, isEmpty);
    });
  });

  group('stillEligible', () {
    test('holds for a plist that is still orphaned', () async {
      final plist = await makePlist(daemons, 'com.example.orphan');
      final responses = {
        ...withProgram(
          plist,
          programArguments0: '/usr/local/opt/example/bin/example',
        ),
        "mdfind kMDItemCFBundleIdentifier == 'com.example.orphan'":
            _mdfindEmpty(),
      };

      expect(await source(responses).stillEligible(plist), isTrue);
    });

    test('refuses once the plist is gone (no Program key readable)', () async {
      final plist = '${daemons.path}/com.example.gone.plist';

      expect(await source(const {}).stillEligible(plist), isFalse);
    });

    test(
      'refuses a helper still referenced by a surviving LaunchDaemon plist',
      () async {
        final helper = await makeHelperFile('com.example.helper');
        final referencingPlist = await makePlist(daemons, 'com.example.owner');

        final responses = {
          "mdfind kMDItemCFBundleIdentifier == 'com.example.helper'":
              _mdfindEmpty(),
          // The referencing plist's Program value is the exact (fake-root)
          // path the helper scan itself discovers, matching what a real
          // /Library/PrivilegedHelperTools path would be in production.
          ...withProgram(referencingPlist, programArguments0: helper),
        };

        expect(await source(responses).stillEligible(helper), isFalse);
      },
    );

    test('holds for a helper no surviving plist references', () async {
      final helper = await makeHelperFile('com.example.helper');
      final responses = {
        "mdfind kMDItemCFBundleIdentifier == 'com.example.helper'":
            _mdfindEmpty(),
      };

      expect(await source(responses).stillEligible(helper), isTrue);
    });
  });

  test(
    'a missing LaunchDaemons/LaunchAgents/PrivilegedHelperTools tree does not throw',
    () async {
      await daemons.delete();
      await agents.delete();
      await helpers.delete();

      expect((await source(const {}).enumerate()).paths, isEmpty);
    },
  );
}
