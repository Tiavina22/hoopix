import 'dart:io';

import 'package:hoopix/features/clean/domain/repositories/whitelist_repository.dart';

/// Where a user's own cleanup whitelist lives. Same shape and filename as
/// Mole's, under hoopix's own directory, so the file is portable between
/// the two.
String whitelistPathFor(String home) => '$home/.config/hoopix/whitelist';

class WhitelistRepositoryImpl implements WhitelistRepository {
  const WhitelistRepositoryImpl({required this.home});

  final String home;

  @override
  String get displayPath => '~/.config/hoopix/whitelist';

  @override
  Future<List<String>?> read() async => readLinesSync(home);

  /// Null when the user has no whitelist file, which is what selects the
  /// convenience defaults rather than an empty list.
  static List<String>? readLinesSync(String home) {
    try {
      final file = File(whitelistPathFor(home));
      if (!file.existsSync()) return null;
      return file.readAsLinesSync();
    } on Object {
      // An unreadable whitelist must not silently mean "protect nothing".
      // Falling back to the defaults keeps the safety rows in place.
      return null;
    }
  }

  /// Written to a sibling file and renamed over the old one, so Clean never
  /// reads a half-written whitelist and a failed write leaves the previous
  /// one intact.
  @override
  Future<void> save(List<String> lines) async {
    final file = File(whitelistPathFor(home));
    await file.parent.create(recursive: true);
    final staging = File('${file.path}.saving');
    await staging.writeAsString('${lines.join('\n')}\n', flush: true);
    await staging.rename(file.path);
  }
}
