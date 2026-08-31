import 'package:hoopix/features/status/domain/entities/system_snapshot.dart';

/// Abstract source of live system-health data. The presentation layer only
/// ever depends on this, never on a concrete datasource — that boundary is
/// what makes the data+domain "engine" swappable without touching the UI.
abstract class StatusRepository {
  Stream<SystemSnapshot> watchStatus({Duration interval = const Duration(seconds: 2)});
}
