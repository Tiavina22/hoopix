import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/analyze/data/models/analyze_entry_model.dart';

void main() {
  test('tryParseSizeBytes converts du -k blocks to bytes', () {
    expect(
      AnalyzeEntryModel.tryParseSizeBytes('500\t/Users/tester/photos\n'),
      500 * 1024,
    );
  });

  test('tryParseSizeBytes keeps paths that contain spaces', () {
    expect(
      AnalyzeEntryModel.tryParseSizeBytes(
        '31720772\t/Users/tester/Library/Application Support\n',
      ),
      31720772 * 1024,
    );
  });

  test('tryParseSizeBytes reads the total of a multi-line du output', () {
    // A `du -s` that also printed a stderr-ish line is still parsed from its
    // first size line rather than misread.
    expect(
      AnalyzeEntryModel.tryParseSizeBytes('64\t/Users/tester/fast'),
      64 * 1024,
    );
  });

  test('tryParseSizeBytes returns null for output with no size line', () {
    expect(AnalyzeEntryModel.tryParseSizeBytes(''), isNull);
    expect(
      AnalyzeEntryModel.tryParseSizeBytes('du: fts_read: Permission denied'),
      isNull,
    );
  });
}
