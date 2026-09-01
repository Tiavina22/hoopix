import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/clean/data/datasources/system_local_datasource.dart';

void main() {
  test(
    'proposes the one curated system cache, tagged for privileged deletion',
    () {
      final result = const SystemLocalDataSource().enumerate();

      expect(result.section, SystemLocalDataSource.system);
      expect(result.paths, ['/Library/Caches/com.apple.iconservices.store']);
      expect(result.privilegedDeletionPaths, {
        '/Library/Caches/com.apple.iconservices.store',
      });
      expect(result.ownerCommands, isEmpty);
    },
  );
}
