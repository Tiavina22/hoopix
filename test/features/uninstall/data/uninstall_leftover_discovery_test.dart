import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_leftover_discovery.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp(
      'hoopix_uninstall_leftovers_',
    );
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

    expect(
      result,
      contains('${home.path}/Library/Application Support/MyApp'),
    );
    expect(
      result,
      isNot(contains('${home.path}/Library/Caches/MyApp')),
    );
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
}
