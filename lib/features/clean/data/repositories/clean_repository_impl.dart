import 'dart:io';

import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/core/platform/privileged_delete.dart';
import 'package:hoopix/core/platform/size_probe.dart';
import 'package:hoopix/core/platform/trash.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/app_leftovers_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/apps_and_utilities_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/developer_tools_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/system_local_datasource.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/entities/clean_whitelist.dart';
import 'package:hoopix/features/clean/domain/entities/path_protection.dart';
import 'package:hoopix/features/clean/domain/repositories/clean_repository.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Sizing a cache tree is the same `du` work Analyze does, and takes the
/// same kind of time on a large one.
const _sizeTimeout = Duration(seconds: 60);

/// An owner command (`npm cache clean --force`, `go clean -modcache`) walks
/// and rewrites a real cache tree, not a quick probe — bounded generously
/// rather than on the same clock as a `du`.
const _ownerCommandTimeout = Duration(minutes: 3);

/// Where a user's own cleanup whitelist lives. Same shape and filename as
/// Mole's, under hoopix's own directory, so the file is portable between
/// the two.
String whitelistPathFor(String home) => '$home/.config/hoopix/whitelist';

class CleanRepositoryImpl implements CleanRepository {
  CleanRepositoryImpl({
    required this.home,
    CleanSectionsLocalDataSource? sections,
    DeveloperToolsLocalDataSource? developerTools,
    AppsAndUtilitiesLocalDataSource? appsAndUtilities,
    AppLeftoversLocalDataSource? appLeftovers,
    SystemLocalDataSource system = const SystemLocalDataSource(),
    SizeProbe? sizeProbe,
    List<String>? Function(String home)? readWhitelist,
    Trash trash = const Trash(),
    PrivilegedDelete privilegedDelete = const PrivilegedDelete(),
    OperationLog? log,
    ProcessRunner? ownerCommandRunner,
  }) : _trash = trash,
       _privilegedDelete = privilegedDelete,
       _system = system,
       _log = log ?? OperationLog(home: home),
       _sections =
           sections ??
           CleanSectionsLocalDataSource(
             home: home,
             denoDir: Platform.environment['DENO_DIR'],
           ),
       _developerTools =
           developerTools ?? DeveloperToolsLocalDataSource(home: home),
       _appsAndUtilities =
           appsAndUtilities ?? AppsAndUtilitiesLocalDataSource(home: home),
       _appLeftovers = appLeftovers ?? AppLeftoversLocalDataSource(home: home),
       _sizeProbe =
           sizeProbe ?? const SizeProbe(ProcessRunner(timeout: _sizeTimeout)),
       _ownerCommandRunner =
           ownerCommandRunner ??
           const ProcessRunner(timeout: _ownerCommandTimeout),
       _readWhitelist = readWhitelist ?? _readWhitelistFile;

  final String home;
  final CleanSectionsLocalDataSource _sections;
  final DeveloperToolsLocalDataSource _developerTools;
  final AppsAndUtilitiesLocalDataSource _appsAndUtilities;
  final AppLeftoversLocalDataSource _appLeftovers;
  final SystemLocalDataSource _system;
  final Trash _trash;
  final PrivilegedDelete _privilegedDelete;
  final OperationLog _log;
  final SizeProbe _sizeProbe;
  final ProcessRunner _ownerCommandRunner;
  final List<String>? Function(String home) _readWhitelist;

  @override
  Stream<CleanPlan> watchPlan() async* {
    final whitelist = CleanWhitelist.from(
      home: home,
      userLines: _readWhitelist(home),
    );

    final plan =
        BuildCleanPlan(
          home: home,
          whitelist: whitelist,
          exists: (path) =>
              FileSystemEntity.typeSync(path, followLinks: false) !=
              FileSystemEntityType.notFound,
          holdsModelCache: holdsCompiledModelCache,
        )([
          ..._sections.enumerate(),
          await _developerTools.enumerate(),
          _appsAndUtilities.enumerate(),
          await _appLeftovers.enumerate(),
          _system.enumerate(),
        ]);

    // Every row is named and grouped before any measuring, so the preview
    // is readable immediately.
    yield plan;

    final eligible = plan.eligible;
    if (eligible.isEmpty) return;

    var sizes = {
      for (final candidate in eligible) candidate.path: candidate.sizeBytes,
    };
    await for (final probe in SizeProbe.pool([
      for (final candidate in eligible) candidate.path,
    ], _sizeProbe.sizeOf)) {
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

    final byTrash = [
      for (final candidate in approved)
        if (!candidate.isOwnerCommand && !candidate.requiresPrivilegedDeletion)
          candidate,
    ];
    final byCommand = [
      for (final candidate in approved)
        if (candidate.isOwnerCommand) candidate,
    ];
    final byPrivilegedDelete = [
      for (final candidate in approved)
        if (candidate.requiresPrivilegedDeletion) candidate,
    ];

    final failures = <String, String>{
      ...await _trash.moveToTrash([
        for (final candidate in byTrash) candidate.path,
      ]),
      // One administrator-privileges prompt for the whole batch, not one
      // per path — approving several System items should not ask twice.
      ...await _privilegedDelete.deletePaths([
        for (final candidate in byPrivilegedDelete) candidate.path,
      ]),
    };
    // Sequential: these run real cache-clean commands, which can be I/O
    // heavy, so overlapping several is worth avoiding rather than saving.
    for (final candidate in byCommand) {
      final failure = await _runOwnerCommand(candidate);
      if (failure != null) failures[candidate.path] = failure;
    }

    for (final candidate in approved) {
      final refusal = failures[candidate.path];
      _log.record(
        command: 'clean',
        outcome: refusal != null
            ? OperationOutcome.refused
            : candidate.isRecoverable
            ? OperationOutcome.trashed
            : OperationOutcome.cleared,
        targetPath: candidate.path,
        detail: refusal,
        sizeBytes: candidate.sizeBytes,
      );
    }
    return failures;
  }

  /// Runs [candidate]'s owner command. Returns null on success, or a failure
  /// message — there is no native refusal channel for this the way Trash
  /// has one, so the process's own exit code is the whole signal.
  Future<String?> _runOwnerCommand(CleanCandidate candidate) async {
    final command = candidate.ownerCommand;
    if (command == null || command.isEmpty) return 'no command to run';
    final result = await _ownerCommandRunner.run(
      command.first,
      command.skip(1).toList(),
    );
    return result.isSuccess ? null : '${result.failure}';
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
