import 'dart:io';

import 'package:hoopix/core/platform/atomic_file.dart' as atomic_file;
import 'package:hoopix/features/purge/domain/entities/purge_discovery.dart';
import 'package:hoopix/features/purge/domain/repositories/purge_paths_repository.dart';

/// Same shape and filename as Mole's `~/.config/mole/purge_paths`, under
/// hoopix's own directory.
String purgePathsFor(String home) => '$home/.config/hoopix/purge_paths';

class PurgePathsRepositoryImpl implements PurgePathsRepository {
  PurgePathsRepositoryImpl({required this.home, PurgeDiscovery? discovery})
    : _discovery = discovery ?? PurgeDiscovery(home: home);

  final String home;
  final PurgeDiscovery _discovery;

  @override
  String get displayPath => '~/.config/hoopix/purge_paths';

  @override
  Future<List<String>?> read() async => readLinesSync(home);

  static List<String>? readLinesSync(String home) =>
      atomic_file.readLinesSync(purgePathsFor(home));

  @override
  Future<void> save(List<String> lines) =>
      atomic_file.writeLinesAtomically(purgePathsFor(home), lines);

  @override
  Future<List<String>> discover() async => _discovery.discover();

  @override
  bool folderExists(String path) =>
      FileSystemEntity.typeSync(path) == FileSystemEntityType.directory;
}
