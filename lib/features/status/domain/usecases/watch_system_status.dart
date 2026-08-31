import 'package:hoopix/features/status/domain/entities/system_snapshot.dart';
import 'package:hoopix/features/status/domain/repositories/status_repository.dart';

/// Thin use case wrapping [StatusRepository.watchStatus] so presentation
/// code depends on an intention-revealing call rather than the repository
/// interface directly.
class WatchSystemStatus {
  const WatchSystemStatus(this._repository);

  final StatusRepository _repository;

  Stream<SystemSnapshot> call({Duration interval = const Duration(seconds: 2)}) {
    return _repository.watchStatus(interval: interval);
  }
}
