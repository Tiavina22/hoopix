import 'package:hoopix/core/platform/du_output.dart';
import 'package:hoopix/features/analyze/domain/entities/analyze_entry.dart';

class AnalyzeEntryModel extends AnalyzeEntry {
  const AnalyzeEntryModel({
    required super.path,
    required super.name,
    required super.isDirectory,
    super.sizeBytes,
    super.accessed,
  });

  /// Kept as a named entry point for the existing tests; the parsing itself
  /// is shared with Clean, which sizes the same way.
  static int? tryParseSizeBytes(String line) => parseDuSizeBytes(line);
}
