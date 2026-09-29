import 'package:hoopix/features/purge/domain/entities/purge_search_roots.dart';
import 'package:hoopix/features/purge/domain/repositories/purge_paths_repository.dart';

class LoadPurgeRoots {
  const LoadPurgeRoots(this._repository, {required this.home});

  final PurgePathsRepository _repository;
  final String home;

  Future<PurgeRootsSelection> call() async => PurgeRootsSelection.load(
    home: home,
    fileLines: await _repository.read(),
    discovered: await _repository.discover(),
  );
}
