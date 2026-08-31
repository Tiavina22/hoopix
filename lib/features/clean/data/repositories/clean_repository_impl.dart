import 'dart:io';

import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/core/platform/size_probe.dart';
import 'package:hoopix/core/platform/trash.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/entities/clean_whitelist.dart';
import 'package:hoopix/features/clean/domain/entities/path_protection.dart';
import 'package:hoopix/features/clean/domain/repositories/clean_repository.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Sizing a cache tree is the same `du` work Analyze does, and takes the
/// same kind of time on a large one.
const _sizeTimeout = Duration(seconds: 60);

/// Where a user's own cleanup whitelist lives. Same shape and filename as
/// Mole's, under hoopix's own directory, so the file is portable between
/// the two.
String whitelistPathFor(String home) => '$home/.config/hoopix/whitelist';

class CleanRepositoryImpl implements CleanRepository {
  CleanRepositoryImpl({
    required this.home,
    CleanSectionsLocalDataSource? sections,
    SizeProbe? sizeProbe,
    List<String>? Function(String home)? readWhitelist,
    Trash trash = const Trash(),
    OperationLog? log,
  }) : _trash = trash,
       _log = log ?? OperationLog(home: home),
       _sections =
           sections ??
           CleanSectionsLocalDataSource(
             home: home,
             denoDir: Platform.environment['DENO_DIR'],
           ),
       _sizeProbe =
           sizeProbe ?? const SizeProbe(ProcessRunner(timeout: _sizeTimeout)),
       _readWhitelist = readWhitelist ?? _readWhitelistFile;

  final String home;
  final CleanSectionsLocalDataSource _sections;
  final Trash _trash;
  final OperationLog _log;
  final SizeProbe _sizeProbe;
  final List<String>? Function(String home) _readWhitelist;

  @override
  Stream<CleanPlan> watchPlan() async* {
    final whitelist = CleanWhitelist.from(
      home: home,
      userLines: _readWhitelist(home),
    );

    final plan = BuildCleanPlan(
      home: home,
      whitelist: whitelist,
      exists: (path) =>
          FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound,
      holdsModelCache: holdsCompiledModelCache,
    )(_sections.enumerate());

    // Every row is named and grouped before any measuring, so the preview
    // is readable immediately.
    yield plan;

    final eligible = plan.eligible;
    if (eligible.isEmpty) return;

    var sizes = {for (final candidate in eligible) candidate.path: candidate.sizeBytes};
    await for (final probe in SizeProbe.pool(
      [for (final candidate in eligible) candidate.path],
      _sizeProbe.sizeOf,
    )) {
      sizes = {...sizes, probe.key: probe.sizeBytes};
      yield CleanPlan(
        candidates: [
          for (final candidate in plan.candidates)
            candidate.isEligible
                ? candidate.withSize(sizes[candidate.path])
                : candidate,
        ],
      );
    }
  }

  @override
  Future<Map<String, String>> approve(List<CleanCandidate> approved) async {
    if (approved.isEmpty) return const {};

    final failures = await _trash.moveToTrash(
      [for (final candidate in approved) candidate.path],
    );

    for (final candidate in approved) {
      final refusal = failures[candidate.path];
      _log.record(
        command: 'clean',
        outcome: refusal == null
            ? OperationOutcome.trashed
            : OperationOutcome.refused,
        targetPath: candidate.path,
        detail: refusal,
        sizeBytes: candidate.sizeBytes,
      );
    }
    return failures;
  }

  /// Null when the user has no whitelist file, which is what selects the
  /// convenience defaults rather than an empty list.
  static List<String>? _readWhitelistFile(String home) {
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
}
