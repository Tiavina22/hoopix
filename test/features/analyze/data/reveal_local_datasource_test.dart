import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/analyze/data/datasources/reveal_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  test('asks Finder to select the path, spaces and all', () async {
    final runner = FakeProcessRunner({
      'open -R /Users/tester/Library/Application Support':
          ProcessResult.success(''),
    });

    final revealed = await RevealLocalDataSource(
      runner,
    ).reveal('/Users/tester/Library/Application Support');

    expect(revealed, isTrue);
  });

  test('refuses paths that must never reach an external command', () async {
    final datasource = RevealLocalDataSource(FakeProcessRunner(const {}));
    // Written this way so no control character sits in the source.
    final withNullByte = '/Users/tester/na${String.fromCharCode(0)}me';

    expect(await datasource.reveal(''), isFalse);
    expect(await datasource.reveal('relative/path'), isFalse);
    expect(await datasource.reveal('/Users/tester/../../etc'), isFalse);
    expect(await datasource.reveal(withNullByte), isFalse);
  });

  test('reports failure when Finder could not be asked', () async {
    final revealed = await RevealLocalDataSource(
      FakeProcessRunner(const {}),
    ).reveal('/Users/tester/Documents');

    expect(revealed, isFalse);
  });
}
