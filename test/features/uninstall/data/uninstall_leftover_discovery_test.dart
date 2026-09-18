import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_leftover_discovery.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_uninstall_leftovers_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  test('only returns candidates that actually exist', () async {
    await Directory(
      '${home.path}/Library/Application Support/MyApp',
    ).create(recursive: true);
    // Caches/MyApp deliberately not created.

    final result = UninstallLeftoverDiscovery().discover(
      home: home.path,
      bundleId: 'com.example.MyApp',
      appName: 'MyApp',
    );

    expect(result, contains('${home.path}/Library/Application Support/MyApp'));
    expect(result, isNot(contains('${home.path}/Library/Caches/MyApp')));
  });

  test('returns nothing when no candidate exists', () async {
    final result = UninstallLeftoverDiscovery().discover(
      home: home.path,
      bundleId: 'com.example.MyApp',
      appName: 'MyApp',
    );

    expect(result, isEmpty);
  });

  test('finds a bundle-id-keyed leftover', () async {
    await File(
      '${home.path}/Library/HTTPStorages/com.example.MyApp.binarycookies',
    ).create(recursive: true);

    final result = UninstallLeftoverDiscovery().discover(
      home: home.path,
      bundleId: 'com.example.MyApp',
      appName: 'MyApp',
    );

    expect(
      result,
      contains(
        '${home.path}/Library/HTTPStorages/com.example.MyApp.binarycookies',
      ),
    );
  });

  group('user LaunchAgents', () {
    Future<void> agent(String name) =>
        File('${home.path}/Library/LaunchAgents/$name').create(recursive: true);

    test('collects bundle-id plists and name-matched plists', () async {
      await agent('com.example.MyAppPro.plist');
      await agent('com.example.MyAppPro.helper.plist');
      await agent('net.other.MyAppPro.updater.plist');
      await agent('com.example.MyAppProfiler.plist');
      await agent('com.apple.MyAppPro.plist');
      await agent('com.unrelated.agent.plist');

      final result = UninstallLeftoverDiscovery().discover(
        home: home.path,
        bundleId: 'com.example.MyAppPro',
        appName: 'MyAppPro',
      );

      final dir = '${home.path}/Library/LaunchAgents';
      expect(
        result,
        containsAll([
          '$dir/com.example.MyAppPro.plist',
          '$dir/com.example.MyAppPro.helper.plist',
          '$dir/net.other.MyAppPro.updater.plist',
          // Contains the display name, exactly like Mole's
          // `-name "*$app_name*.plist"`.
          '$dir/com.example.MyAppProfiler.plist',
        ]),
      );
      expect(result, isNot(contains('$dir/com.apple.MyAppPro.plist')));
      expect(result, isNot(contains('$dir/com.unrelated.agent.plist')));
    });

    test('a demoted bundle id and an empty name collect no agents', () async {
      await agent('com.example.MyAppPro.plist');

      final result = UninstallLeftoverDiscovery().discover(
        home: home.path,
        bundleId: 'unknown',
        appName: '',
      );

      expect(result, isEmpty);
    });

    test('a demoted bundle id keeps name-matched agents only', () async {
      await agent('com.example.helper.plist');
      await agent('net.vendor.MyAppPro.plist');

      final result = UninstallLeftoverDiscovery().discover(
        home: home.path,
        bundleId: 'unknown',
        appName: 'MyAppPro',
      );

      expect(result, [
        '${home.path}/Library/LaunchAgents/net.vendor.MyAppPro.plist',
      ]);
    });
  });
}
