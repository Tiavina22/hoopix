import 'package:hoopix/features/purge/domain/entities/purge_search_roots.dart';
import 'package:hoopix/features/purge/domain/repositories/purge_paths_repository.dart';

class SavePurgeRoots {
  const SavePurgeRoots(this._repository);

  final PurgePathsRepository _repository;

  Future<void> call(PurgeRootsSelection selection) =>
      _repository.save(selection.toFileLines());
}
