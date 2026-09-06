import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/size_probe.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_app_discovery.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_leftover_discovery.dart';
import 'package:hoopix/features/uninstall/data/repositories/uninstall_inventory_repository_impl.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  late Directory home;
  late Directory applicationsStub;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_uninstall_repo_home_');
    applicationsStub = await Directory.systemTemp.createTemp(
      'hoopix_uninstall_repo_apps_',
    );
  });

  tearDown(() async {
    for (final dir in [home, applicationsStub]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  Directory redirect(String path) {
    if (path == '/Applications' || path.startsWith('/Applications/')) {
      return Directory(
        path.replaceFirst('/Applications', applicationsStub.path),
      );
    }
    return Directory(path);
  }

  test('lists an app with its leftovers and eventual size', () async {
    final app = await Directory(
      '${applicationsStub.path}/MyApp.app',
    ).create(recursive: true);
    await File('${app.path}/Contents/Info.plist').create(recursive: true);
    await Directory(
      '${home.path}/Library/Application Support/MyApp',
    ).create(recursive: true);

    final plist = '${app.path}/Contents/Info.plist';
    final probe = FakeProcessRunner({
      'plutil -extract CFBundleIdentifier raw $plist': ProcessResult.success(
        'com.example.MyApp\n',
      ),
      'plutil -extract LSBackgroundOnly raw $plist': ProcessResult.success(
        '0\n',
      ),
      'plutil -extract CFBundleDisplayName raw $plist': ProcessResult.success(
        'MyApp\n',
      ),
      'plutil -extract CFBundleName raw $plist': ProcessResult.success(
        'MyApp\n',
      ),
      'du -skPx ${app.path}': ProcessResult.success('4096\t${app.path}'),
    });

    final repository = UninstallInventoryRepositoryImpl(
      home: home.path,
      appDiscovery: UninstallAppDiscovery(
        home: home.path,
        probe: probe,
        directory: redirect,
      ),
      leftoverDiscovery: UninstallLeftoverDiscovery(),
      sizeProbe: SizeProbe(probe),
    );

    final snapshots = await repository.watchInventory().toList();

    final first = snapshots.first.single;
    expect(first.path, app.path);
    expect(first.bundleId, 'com.example.MyApp');
    expect(
      first.leftoverPaths,
      contains('${home.path}/Library/Application Support/MyApp'),
    );
    expect(first.sizeBytes, isNull);

    final last = snapshots.last.single;
    expect(last.sizeBytes, 4096 * 1024);
    // Sizing never disturbs what was already found.
    expect(last.leftoverPaths, first.leftoverPaths);
  });

  test('emits an empty list and stops when nothing is installed', () async {
    final repository = UninstallInventoryRepositoryImpl(
      home: home.path,
      appDiscovery: UninstallAppDiscovery(
        home: home.path,
        probe: FakeProcessRunner(const {}),
        directory: redirect,
      ),
    );

    final snapshots = await repository.watchInventory().toList();

    expect(snapshots, [isEmpty]);
  });
}
