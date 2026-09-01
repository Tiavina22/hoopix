import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_firmware_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeFile(String relative) =>
      File('${home.path}/$relative').create(recursive: true);

  List<String> targets() => CleanSectionsLocalDataSource(home: home.path)
      .enumerate()
      .singleWhere(
        (section) =>
            section.section == CleanSectionsLocalDataSource.deviceFirmware,
      )
      .paths;

  test('reaches .ipsw files under each iTunes device-kind folder', () async {
    await makeFile(
      'Library/iTunes/iPhone Software Updates/iPhone16,2_18.0_22A3354.ipsw',
    );
    await makeFile('Library/iTunes/iPad Software Updates/iPad14,1_18.0.ipsw');
    await makeFile('Library/iTunes/iPod Software Updates/iPod9,1_15.8.ipsw');

    final result = targets();

    expect(
      result,
      contains(
        '${home.path}/Library/iTunes/iPhone Software Updates/iPhone16,2_18.0_22A3354.ipsw',
      ),
    );
    expect(
      result,
      contains(
        '${home.path}/Library/iTunes/iPad Software Updates/iPad14,1_18.0.ipsw',
      ),
    );
    expect(
      result,
      contains(
        '${home.path}/Library/iTunes/iPod Software Updates/iPod9,1_15.8.ipsw',
      ),
    );
  });

  test('ignores a non-ipsw file in the same folder', () async {
    await makeFile('Library/iTunes/iPhone Software Updates/readme.txt');

    expect(
      targets(),
      isNot(
        contains(
          '${home.path}/Library/iTunes/iPhone Software Updates/readme.txt',
        ),
      ),
    );
  });

  test(
    'reaches .ipsw files nested under an Apple Configurator group container',
    () async {
      await makeFile(
        'Library/Group Containers/ABCDE12345.group.com.apple.configurator'
        '/Library/Caches/firmware/iPhone16,2_18.0.ipsw',
      );

      expect(
        targets(),
        contains(
          '${home.path}/Library/Group Containers/ABCDE12345.group.com.apple.configurator'
          '/Library/Caches/firmware/iPhone16,2_18.0.ipsw',
        ),
      );
    },
  );

  test('never looks inside an unrelated group container', () async {
    await makeFile(
      'Library/Group Containers/group.com.apple.notes/firmware.ipsw',
    );

    expect(
      targets(),
      isNot(
        contains(
          '${home.path}/Library/Group Containers/group.com.apple.notes/firmware.ipsw',
        ),
      ),
    );
  });

  test('a missing home tree does not throw', () {
    expect(targets, returnsNormally);
  });
}
