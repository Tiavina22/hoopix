import 'package:hoopix/features/clean/domain/entities/whitelist_selection.dart';
import 'package:hoopix/features/clean/domain/repositories/whitelist_repository.dart';

class SaveWhitelist {
  const SaveWhitelist(this._repository);

  final WhitelistRepository _repository;

  Future<void> call(WhitelistSelection selection) =>
      _repository.save(selection.toFileLines());
}
