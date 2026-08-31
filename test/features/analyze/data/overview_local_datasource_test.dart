import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/analyze/data/datasources/overview_local_datasource.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';
import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';

import '../../../support/fake_process_runner.dart';

String _duLine(int kilobytes, String path) => '$kilobytes\t$path\n';

AnalyzeEntry? _row(DirectoryScan scan, OverviewRowKind kind) {
  for (final entry in scan.entries) {
    if (entry.overviewKind == kind) return entry;
  }
  return null;
}

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hoopix_overview_');
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  test('lists the structural roots with Home first', () async {
    final scans = await OverviewLocalDataSource(
      FakeProcessRunner(const {}),
      home: home.path,
    ).watch().toList();

    // Rows are named and on screen before any measurement lands.
    expect(scans.first.status, DirectoryScanStatus.scanning);
    expect(_row(scans.first, OverviewRowKind.home), isNotNull);
    // /Applications and /Library exist on any Mac this runs on.
    expect(_row(scans.first, OverviewRowKind.applications), isNotNull);
    expect(_row(scans.first, OverviewRowKind.systemLibrary), isNotNull);
  });

  test('only surfaces insight rows whose path exists', () async {
    final withoutBackups = await OverviewLocalDataSource(
      FakeProcessRunner(const {}),
      home: home.path,
    ).watch().first;
    expect(_row(withoutBackups, OverviewRowKind.iosBackups), isNull);

    await Directory(
      '${home.path}/Library/Application Support/MobileSync/Backup',
    ).create(recursive: true);

    final withBackups = await OverviewLocalDataSource(
      FakeProcessRunner(const {}),
      home: home.path,
    ).watch().first;
    expect(_row(withBackups, OverviewRowKind.iosBackups), isNotNull);
  });

  test('measures Home without counting ~/Library twice', () async {
    await Directory('${home.path}/Library').create();
    await Directory('${home.path}/Documents').create();
    await File('${home.path}/loose.txt').writeAsString('x' * 50);

    final runner = FakeProcessRunner({
      'du -skPx ${home.path}/Documents': ProcessResult.success(
        _duLine(10, '${home.path}/Documents'),
      ),
      // Present, and deliberately never asked for by the Home measurement.
      'du -skPx ${home.path}/Library': ProcessResult.success(
        _duLine(99999, '${home.path}/Library'),
      ),
    });

    final scans = await OverviewLocalDataSource(
      runner,
      home: home.path,
    ).watch().toList();

    // Documents + the loose file, with ~/Library excluded — it has its own row.
    expect(_row(scans.last, OverviewRowKind.home)!.sizeBytes, 10 * 1024 + 50);
    expect(
      _row(scans.last, OverviewRowKind.userLibrary)!.sizeBytes,
      99999 * 1024,
    );
  });

  test('Old Downloads counts only entries older than 90 days', () async {
    final downloads = await Directory('${home.path}/Downloads').create();
    final old = File('${downloads.path}/old.zip');
    await old.writeAsString('x' * 300);
    await old.setLastModified(
      DateTime.now().subtract(const Duration(days: 120)),
    );

    final recent = File('${downloads.path}/recent.zip');
    await recent.writeAsString('x' * 900);

    final hidden = File('${downloads.path}/.hidden');
    await hidden.writeAsString('x' * 500);
    await hidden.setLastModified(
      DateTime.now().subtract(const Duration(days: 200)),
    );

    final scans = await OverviewLocalDataSource(
      FakeProcessRunner(const {}),
      home: home.path,
    ).watch().toList();

    // The recent file and the hidden one are both left out.
    expect(_row(scans.last, OverviewRowKind.oldDownloads)!.sizeBytes, 300);
  });

  test('surfaces a tool cache under its product name', () async {
    await Directory('${home.path}/Library/Caches/Homebrew').create(
      recursive: true,
    );

    final runner = FakeProcessRunner({
      'du -skPx ${home.path}/Library/Caches/Homebrew': ProcessResult.success(
        _duLine(2048, '${home.path}/Library/Caches/Homebrew'),
      ),
    });

    final scans = await OverviewLocalDataSource(
      runner,
      home: home.path,
    ).watch().toList();

    final tools = scans.last.entries
        .where((entry) => entry.overviewKind == OverviewRowKind.tool)
        .toList();
    expect(tools.map((entry) => entry.name), contains('Homebrew Cache'));
    expect(
      tools.firstWhere((entry) => entry.name == 'Homebrew Cache').sizeBytes,
      2048 * 1024,
    );
  });

  test('an unknown HOME yields an empty overview instead of throwing', () async {
    final scans = await OverviewLocalDataSource(
      FakeProcessRunner(const {}),
      home: null,
    ).watch().toList();

    expect(scans.single.status, DirectoryScanStatus.loaded);
    expect(scans.single.entries, isEmpty);
  });
}
