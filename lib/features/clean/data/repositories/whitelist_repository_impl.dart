import 'package:hoopix/core/platform/atomic_file.dart' as atomic_file;
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
  static List<String>? readLinesSync(String home) =>
      // An unreadable whitelist must not silently mean "protect nothing":
      // null falls back to the defaults, which keeps the safety rows.
      atomic_file.readLinesSync(whitelistPathFor(home));

  /// Atomic, so Clean never reads a half-written whitelist.
  @override
  Future<void> save(List<String> lines) =>
      atomic_file.writeLinesAtomically(whitelistPathFor(home), lines);
}
