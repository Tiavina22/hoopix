import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_virtualization_home_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> makeDir(String relative) =>
      Directory('${home.path}/$relative').create(recursive: true);

  List<String> targets() => CleanSectionsLocalDataSource(home: home.path)
      .enumerate()
      .singleWhere(
        (section) =>
            section.section == CleanSectionsLocalDataSource.virtualization,
      )
      .paths;

  test(
    'reaches VMware Fusion, since its cache is blanket-protected whole',
    () async {
      await makeDir('Library/Caches/com.vmware.fusion');

      expect(
        targets(),
        contains('${home.path}/Library/Caches/com.vmware.fusion'),
      );
    },
  );

  test(
    'never proposes Parallels or Lima, already swept whole elsewhere',
    () async {
      await makeDir('Library/Caches/com.parallels.desktop.console/blob');
      await makeDir('Library/Caches/lima/download/by-url-sha256/blob');

      final result = targets();

      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Caches/com.parallels.desktop.console/blob',
          ),
        ),
      );
      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Caches/lima/download/by-url-sha256/blob',
          ),
        ),
      );
    },
  );

  test('sweeps VirtualBox and Vagrant temp files directly', () async {
    await makeDir('VirtualBox VMs/.cache');
    await makeDir('.vagrant.d/tmp/blob');

    final result = targets();

    expect(result, contains('${home.path}/VirtualBox VMs/.cache'));
    expect(result, contains('${home.path}/.vagrant.d/tmp/blob'));
  });

  test('a missing home tree does not throw', () {
    expect(targets, returnsNormally);
  });
}
