import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_app_discovery.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _missing() =>
    ProcessResult.failure(ProcessFailure.notFound('plutil', 'missing key'));

void main() {
  late Directory home;
  late Directory applicationsStub;
  late Directory inputMethodsStub;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_uninstall_home_');
    applicationsStub = await Directory.systemTemp.createTemp(
      'hoopix_uninstall_apps_',
    );
    inputMethodsStub = await Directory.systemTemp.createTemp(
      'hoopix_uninstall_im_',
    );
  });

  tearDown(() async {
    for (final dir in [home, applicationsStub, inputMethodsStub]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  Directory redirect(String path) {
    if (path == '/Applications' || path.startsWith('/Applications/')) {
      return Directory(
        path.replaceFirst('/Applications', applicationsStub.path),
      );
    }
    if (path == '/Library/Input Methods' ||
        path.startsWith('/Library/Input Methods/')) {
      return Directory(
        path.replaceFirst('/Library/Input Methods', inputMethodsStub.path),
      );
    }
    return Directory(path);
  }

  UninstallAppDiscovery discovery({
    Map<String, ProcessResult> probeResponses = const {},
  }) => UninstallAppDiscovery(
    home: home.path,
    probe: FakeProcessRunner(probeResponses),
    directory: redirect,
  );

  Future<Directory> makeApp(String relativeToApplications) async {
    final appDir = await Directory(
      '${applicationsStub.path}/$relativeToApplications',
    ).create(recursive: true);
    await File('${appDir.path}/Contents/Info.plist').create(recursive: true);
    return appDir;
  }

  Map<String, ProcessResult> plistResponses(
    String appPath, {
    String? bundleId,
    String? displayName,
    String? bundleName,
    bool backgroundOnly = false,
  }) {
    final plist = '$appPath/Contents/Info.plist';
    return {
      'plutil -extract CFBundleIdentifier raw $plist': bundleId == null
          ? _missing()
          : ProcessResult.success('$bundleId\n'),
      'plutil -extract LSBackgroundOnly raw $plist': ProcessResult.success(
        backgroundOnly ? '1\n' : '0\n',
      ),
      'plutil -extract CFBundleDisplayName raw $plist': displayName == null
          ? _missing()
          : ProcessResult.success('$displayName\n'),
      'plutil -extract CFBundleName raw $plist': bundleName == null
          ? _missing()
          : ProcessResult.success('$bundleName\n'),
    };
  }

  test('finds an ordinary app directly in /Applications', () async {
    final app = await makeApp('MyApp.app');

    final apps = await discovery(
      probeResponses: plistResponses(
        app.path,
        bundleId: 'com.example.MyApp',
        displayName: 'MyApp',
      ),
    ).discover();

    expect(apps, hasLength(1));
    expect(apps.single.path, app.path);
    expect(apps.single.bundleId, 'com.example.MyApp');
    expect(apps.single.displayName, 'MyApp');
  });

  test('reports unknown when the bundle id cannot be read', () async {
    final app = await makeApp('NoPlistId.app');

    final apps = await discovery(
      probeResponses: plistResponses(app.path),
    ).discover();

    expect(apps.single.bundleId, 'unknown');
  });

  test('never lists a system-critical bundle', () async {
    final app = await makeApp('Finder.app');

    final apps = await discovery(
      probeResponses: plistResponses(app.path, bundleId: 'com.apple.finder'),
    ).discover();

    expect(apps, isEmpty);
  });

  test('the Apple-uninstallable override still lists a pro app that would '
      'otherwise look critical', () async {
    final app = await makeApp('Xcode.app');

    final apps = await discovery(
      probeResponses: plistResponses(
        app.path,
        bundleId: 'com.apple.dt.Xcode',
        displayName: 'Xcode',
      ),
    ).discover();

    expect(apps, hasLength(1));
  });

  test('never lists an app nested inside another .app bundle', () async {
    final nested = await Directory(
      '${applicationsStub.path}/Outer.app/Contents/Resources/Inner.app',
    ).create(recursive: true);
    await File('${nested.path}/Contents/Info.plist').create(recursive: true);

    final apps = await discovery(
      probeResponses: plistResponses(
        nested.path,
        bundleId: 'com.example.Inner',
      ),
    ).discover();

    expect(apps.where((a) => a.path == nested.path), isEmpty);
  });

  test(
    'excludes a background-only helper that is not directly in a search root',
    () async {
      final helper = await makeApp('Vendor/Helper.app');

      final apps = await discovery(
        probeResponses: plistResponses(
          helper.path,
          bundleId: 'com.example.Helper',
          backgroundOnly: true,
        ),
      ).discover();

      expect(apps, isEmpty);
    },
  );

  test(
    'keeps a background-only app that is directly in a search root',
    () async {
      final app = await makeApp('DirectHelper.app');

      final apps = await discovery(
        probeResponses: plistResponses(
          app.path,
          bundleId: 'com.example.DirectHelper',
          backgroundOnly: true,
        ),
      ).discover();

      expect(apps, hasLength(1));
    },
  );

  test(
    'prefers CFBundleDisplayName, then CFBundleName, then the basename',
    () async {
      final withDisplayName = await makeApp('WithDisplay.app');
      final withBundleNameOnly = await makeApp('WithBundleName.app');
      final withNeither = await makeApp('Basename.app');

      final responses = {
        ...plistResponses(
          withDisplayName.path,
          bundleId: 'com.example.a',
          displayName: 'Pretty Name',
          bundleName: 'Ignored',
        ),
        ...plistResponses(
          withBundleNameOnly.path,
          bundleId: 'com.example.b',
          bundleName: 'Bundle Name',
        ),
        ...plistResponses(withNeither.path, bundleId: 'com.example.c'),
      };

      final apps = await discovery(probeResponses: responses).discover();
      final byPath = {for (final a in apps) a.path: a.displayName};

      expect(byPath[withDisplayName.path], 'Pretty Name');
      expect(byPath[withBundleNameOnly.path], 'Bundle Name');
      expect(byPath[withNeither.path], 'Basename');
    },
  );

  test(
    'keeps a versioned basename distinct when metadata would collapse it',
    () async {
      final app = await makeApp('App 2.app');

      final apps = await discovery(
        probeResponses: plistResponses(
          app.path,
          bundleId: 'com.example.App2',
          displayName: 'App',
        ),
      ).discover();

      expect(apps.single.displayName, 'App 2');
    },
  );

  test('finds an app under \$HOME/Applications too', () async {
    final userApp = await Directory(
      '${home.path}/Applications/UserApp.app',
    ).create(recursive: true);
    await File('${userApp.path}/Contents/Info.plist').create(recursive: true);

    final apps = await discovery(
      probeResponses: plistResponses(
        userApp.path,
        bundleId: 'com.example.UserApp',
      ),
    ).discover();

    expect(apps.map((a) => a.path), contains(userApp.path));
  });

  test('does not throw when a search root does not exist', () async {
    final apps = await discovery().discover();
    expect(apps, isEmpty);
  });
}
