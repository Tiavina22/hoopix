import 'package:hoopix/features/analyze/domain/entities/directory_scan.dart';
import 'package:hoopix/features/analyze/domain/repositories/analyze_repository.dart';

/// Thin use case wrapping [AnalyzeRepository.watchDirectory] so presentation
/// code depends on an intention-revealing call rather than the repository
/// interface directly.
class WatchDirectory {
  const WatchDirectory(this._repository);

  final AnalyzeRepository _repository;

  /// An empty [path] means the curated overview rather than a directory —
  /// see [overviewPath].
  Stream<DirectoryScan> call(String path) => path == overviewPath
      ? _repository.watchOverview()
      : _repository.watchDirectory(path);
}
