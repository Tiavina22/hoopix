import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_cloud_office_home_');
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
            section.section == CleanSectionsLocalDataSource.cloudAndOffice,
      )
      .paths;

  test(
    'reaches Box, since its cache is blanket-protected as a top-level directory',
    () async {
      await makeDir('Library/Caches/com.box.desktop');

      expect(
        targets(),
        contains('${home.path}/Library/Caches/com.box.desktop'),
      );
    },
  );

  test(
    'never proposes Baidu Netdisk or Alibaba Cloud, already swept whole elsewhere',
    () async {
      await makeDir('Library/Caches/com.baidu.netdisk/blob');
      await makeDir('Library/Caches/com.alibaba.teambitiondisk/blob');

      final result = targets();

      expect(
        result,
        isNot(contains('${home.path}/Library/Caches/com.baidu.netdisk/blob')),
      );
      expect(
        result,
        isNot(
          contains(
            '${home.path}/Library/Caches/com.alibaba.teambitiondisk/blob',
          ),
        ),
      );
    },
  );

  group('Microsoft Office', () {
    test('reaches Word, Excel and PowerPoint top-level caches whole', () async {
      await makeDir('Library/Caches/com.microsoft.Word');
      await makeDir('Library/Caches/com.microsoft.Excel');
      await makeDir('Library/Caches/com.microsoft.Powerpoint');

      final result = targets();

      expect(
        result,
        contains('${home.path}/Library/Caches/com.microsoft.Word'),
      );
      expect(
        result,
        contains('${home.path}/Library/Caches/com.microsoft.Excel'),
      );
      expect(
        result,
        contains('${home.path}/Library/Caches/com.microsoft.Powerpoint'),
      );
    });

    test('reaches Word and Excel container caches, temp files and logs', () async {
      await makeDir(
        'Library/Containers/com.microsoft.Word/Data/Library/Caches/blob',
      );
      await makeDir('Library/Containers/com.microsoft.Word/Data/tmp/blob');
      await makeDir(
        'Library/Containers/com.microsoft.Word/Data/Library/Logs/blob',
      );
      await makeDir(
        'Library/Containers/com.microsoft.Excel/Data/Library/Caches/blob',
      );
      await makeDir('Library/Containers/com.microsoft.Excel/Data/tmp/blob');
      await makeDir(
        'Library/Containers/com.microsoft.Excel/Data/Library/Logs/blob',
      );

      final result = targets();

      for (final app in ['Word', 'Excel']) {
        expect(
          result,
          contains(
            '${home.path}/Library/Containers/com.microsoft.$app/Data/Library/Caches/blob',
          ),
        );
        expect(
          result,
          contains(
            '${home.path}/Library/Containers/com.microsoft.$app/Data/tmp/blob',
          ),
        );
        expect(
          result,
          contains(
            '${home.path}/Library/Containers/com.microsoft.$app/Data/Library/Logs/blob',
          ),
        );
      }
    });

    test('reaches Outlook cache through its children', () async {
      await makeDir('Library/Caches/com.microsoft.Outlook/blob');

      expect(
        targets(),
        contains('${home.path}/Library/Caches/com.microsoft.Outlook/blob'),
      );
    });
  });

  test('reaches every iWork app cache by prefix', () async {
    await makeDir('Library/Caches/com.apple.iWork.Pages');
    await makeDir('Library/Caches/com.apple.iWork.Numbers');
    await makeDir('Library/Caches/com.apple.iWork.Keynote');

    final result = targets();

    expect(
      result,
      contains('${home.path}/Library/Caches/com.apple.iWork.Pages'),
    );
    expect(
      result,
      contains('${home.path}/Library/Caches/com.apple.iWork.Numbers'),
    );
    expect(
      result,
      contains('${home.path}/Library/Caches/com.apple.iWork.Keynote'),
    );
  });

  test('never proposes WPS Office, already swept whole elsewhere', () async {
    await makeDir('Library/Caches/com.kingsoft.wpsoffice.mac/blob');

    expect(
      targets(),
      isNot(
        contains('${home.path}/Library/Caches/com.kingsoft.wpsoffice.mac/blob'),
      ),
    );
  });

  test(
    'reaches Thunderbird and Apple Mail caches through their children',
    () async {
      await makeDir('Library/Caches/org.mozilla.thunderbird/blob');
      await makeDir('Library/Caches/com.apple.mail/blob');

      final result = targets();

      expect(
        result,
        contains('${home.path}/Library/Caches/org.mozilla.thunderbird/blob'),
      );
      expect(
        result,
        contains('${home.path}/Library/Caches/com.apple.mail/blob'),
      );
    },
  );

  test('a missing home tree does not throw', () {
    expect(targets, returnsNormally);
  });
}
