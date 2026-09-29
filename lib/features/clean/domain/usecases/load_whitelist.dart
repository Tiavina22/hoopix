import 'package:hoopix/features/clean/domain/entities/whitelist_selection.dart';
import 'package:hoopix/features/clean/domain/repositories/whitelist_repository.dart';

class LoadWhitelist {
  const LoadWhitelist(this._repository, {required this.home});

  final WhitelistRepository _repository;
  final String home;

  Future<WhitelistSelection> call() async =>
      WhitelistSelection.load(home: home, fileLines: await _repository.read());
}
