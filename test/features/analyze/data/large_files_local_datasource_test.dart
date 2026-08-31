import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/analyze/data/datasources/large_files_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hoopix_large_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// Spotlight is asked for files at or above 100 MB.
  String query(String path) =>
      'mdfind -onlyin $path kMDItemFSSize >= ${100 * 1024 * 1024}';

  Future<File> makeFile(String relative, int bytes) async {
    final file = File('${root.path}/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsString('x' * bytes);
    return file;
  }

  test('returns Spotlight hits largest first, sized from disk', () async {
    final small = await makeFile('small.mov', 100);
    final big = await makeFile('big.mov', 900);

    final runner = FakeProcessRunner({
      query(root.path): ProcessResult.success('${small.path}\n${big.path}\n'),
    });

    final files = await LargeFilesLocalDataSource(
      FakeProcessRunner({}),
    ).find(root.path);
    expect(files, isEmpty); // no fake response configured

    final found = await LargeFilesLocalDataSource(runner).find(root.path);
    expect(found.map((file) => file.name), ['big.mov', 'small.mov']);
    expect(found.first.sizeBytes, 900);
    expect(found.every((file) => file.isDirectory), isFalse);
  });

  test('skips source and text files even when Spotlight returns them', () async {
    final code = await makeFile('dump.sql', 500);
    final movie = await makeFile('movie.mov', 100);

    final runner = FakeProcessRunner({
      query(root.path): ProcessResult.success('${code.path}\n${movie.path}\n'),
    });

    final found = await LargeFilesLocalDataSource(runner).find(root.path);

    expect(found.map((file) => file.name), ['movie.mov']);
  });

  test('skips hits inside build, dependency and cache directories', () async {
    final vendored = await makeFile('node_modules/pkg/blob.bin', 500);
    final own = await makeFile('blob.bin', 100);

    final runner = FakeProcessRunner({
      query(root.path): ProcessResult.success('${vendored.path}\n${own.path}\n'),
    });

    final found = await LargeFilesLocalDataSource(runner).find(root.path);

    expect(found.map((file) => file.path), [own.path]);
  });

  test('drops hits the index still lists but that are gone', () async {
    final present = await makeFile('present.iso', 100);

    final runner = FakeProcessRunner({
      query(root.path): ProcessResult.success(
        '${root.path}/vanished.iso\n${present.path}\n',
      ),
    });

    final found = await LargeFilesLocalDataSource(runner).find(root.path);

    expect(found.map((file) => file.name), ['present.iso']);
  });

  test('a directory hit is never listed as a file', () async {
    final directory = Directory('${root.path}/bundle.app');
    await directory.create();

    final runner = FakeProcessRunner({
      query(root.path): ProcessResult.success('${directory.path}\n'),
    });

    final found = await LargeFilesLocalDataSource(runner).find(root.path);

    expect(found, isEmpty);
  });

  test('an unavailable Spotlight yields nothing rather than throwing', () async {
    final found = await LargeFilesLocalDataSource(
      FakeProcessRunner({}),
    ).find('/nope');

    expect(found, isEmpty);
  });
}
