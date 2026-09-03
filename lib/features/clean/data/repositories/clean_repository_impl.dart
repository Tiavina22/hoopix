import 'dart:io';

import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/core/platform/privileged_delete.dart';
import 'package:hoopix/core/platform/size_probe.dart';
import 'package:hoopix/core/platform/trash.dart';
import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/app_leftovers_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/apps_and_utilities_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/autodesk_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/browser_profile_caches_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/chromium_old_versions_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/cloud_storage_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/developer_tools_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/edge_updater_old_versions_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/final_cut_pro_generated_caches_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/jianying_pro_generated_caches_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/macos_installer_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/orphaned_system_services_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/pnpm_store_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/simulator_caches_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/system_aged_sweeps_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/system_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/tart_cache_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/utm_caches_local_datasource.dart';
import 'package:hoopix/features/clean/data/datasources/xcode_caches_local_datasource.dart';
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
    BrowserProfileCachesLocalDataSource? browserProfileCaches,
    XcodeCachesLocalDataSource? xcodeCaches,
    CloudStorageLocalDataSource? cloudStorage,
    UtmCachesLocalDataSource? utmCaches,
    TartCacheLocalDataSource? tartCache,
    FinalCutProGeneratedCachesLocalDataSource? finalCutProGeneratedCaches,
    JianyingProGeneratedCachesLocalDataSource? jianyingProGeneratedCaches,
    PnpmStoreLocalDataSource? pnpmStore,
    MacosInstallerLocalDataSource? macosInstaller,
    ChromiumOldVersionsLocalDataSource? chromiumOldVersions,
    EdgeUpdaterOldVersionsLocalDataSource? edgeUpdaterOldVersions,
    AutodeskLocalDataSource? autodesk,
    SimulatorCachesLocalDataSource? simulatorCaches,
    SystemAgedSweepsLocalDataSource? systemAgedSweeps,
    OrphanedSystemServicesLocalDataSource? orphanedSystemServices,
    SystemLocalDataSource system = const SystemLocalDataSource(),
    SizeProbe? sizeProbe,
    List<String>? Function(String home)? readWhitelist,
    Trash trash = const Trash(),
    PrivilegedDelete privilegedDelete = const PrivilegedDelete(),
    OperationLog? log,
    ProcessRunner? ownerCommandRunner,
    ProcessGuard? recheckGuard,
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
       _browserProfileCaches =
           browserProfileCaches ??
           BrowserProfileCachesLocalDataSource(home: home),
       _xcodeCaches = xcodeCaches ?? XcodeCachesLocalDataSource(home: home),
       _cloudStorage = cloudStorage ?? CloudStorageLocalDataSource(home: home),
       _utmCaches = utmCaches ?? UtmCachesLocalDataSource(home: home),
       _tartCache = tartCache ?? TartCacheLocalDataSource(home: home),
       _finalCutProGeneratedCaches =
           finalCutProGeneratedCaches ??
           FinalCutProGeneratedCachesLocalDataSource(home: home),
       _jianyingProGeneratedCaches =
           jianyingProGeneratedCaches ??
           JianyingProGeneratedCachesLocalDataSource(home: home),
       _pnpmStore = pnpmStore ?? PnpmStoreLocalDataSource(home: home),
       _macosInstaller = macosInstaller ?? MacosInstallerLocalDataSource(),
       _chromiumOldVersions =
           chromiumOldVersions ??
           ChromiumOldVersionsLocalDataSource(home: home),
       _edgeUpdaterOldVersions =
           edgeUpdaterOldVersions ??
           EdgeUpdaterOldVersionsLocalDataSource(home: home),
       _autodesk = autodesk ?? AutodeskLocalDataSource(home: home),
       _simulatorCaches =
           simulatorCaches ?? SimulatorCachesLocalDataSource(home: home),
       _systemAgedSweeps =
           systemAgedSweeps ?? SystemAgedSweepsLocalDataSource(),
       _orphanedSystemServices =
           orphanedSystemServices ??
           OrphanedSystemServicesLocalDataSource(home: home),
       _sizeProbe =
           sizeProbe ?? const SizeProbe(ProcessRunner(timeout: _sizeTimeout)),
       _ownerCommandRunner =
           ownerCommandRunner ??
           const ProcessRunner(timeout: _ownerCommandTimeout),
       _recheckGuard =
           recheckGuard ??
           const ProcessGuard(ProcessRunner(timeout: Duration(seconds: 5))),
       _readWhitelist = readWhitelist ?? _readWhitelistFile;

  final String home;
  final CleanSectionsLocalDataSource _sections;
  final DeveloperToolsLocalDataSource _developerTools;
  final AppsAndUtilitiesLocalDataSource _appsAndUtilities;
  final AppLeftoversLocalDataSource _appLeftovers;
  final BrowserProfileCachesLocalDataSource _browserProfileCaches;
  final XcodeCachesLocalDataSource _xcodeCaches;
  final CloudStorageLocalDataSource _cloudStorage;
  final UtmCachesLocalDataSource _utmCaches;
  final TartCacheLocalDataSource _tartCache;
  final FinalCutProGeneratedCachesLocalDataSource _finalCutProGeneratedCaches;
  final JianyingProGeneratedCachesLocalDataSource _jianyingProGeneratedCaches;
  final PnpmStoreLocalDataSource _pnpmStore;
  final MacosInstallerLocalDataSource _macosInstaller;
  final ChromiumOldVersionsLocalDataSource _chromiumOldVersions;
  final EdgeUpdaterOldVersionsLocalDataSource _edgeUpdaterOldVersions;
  final AutodeskLocalDataSource _autodesk;
  final SimulatorCachesLocalDataSource _simulatorCaches;
  final SystemAgedSweepsLocalDataSource _systemAgedSweeps;
  final OrphanedSystemServicesLocalDataSource _orphanedSystemServices;
  final SystemLocalDataSource _system;
  final Trash _trash;
  final PrivilegedDelete _privilegedDelete;
  final OperationLog _log;
  final SizeProbe _sizeProbe;
  final ProcessRunner _ownerCommandRunner;
  final ProcessGuard _recheckGuard;
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
          await _browserProfileCaches.enumerate(),
          await _xcodeCaches.enumerate(),
          await _cloudStorage.enumerate(),
          await _utmCaches.enumerate(),
          await _tartCache.enumerate(),
          await _finalCutProGeneratedCaches.enumerate(),
          await _jianyingProGeneratedCaches.enumerate(),
          await _pnpmStore.enumerate(),
          await _macosInstaller.enumerate(),
          await _chromiumOldVersions.enumerate(),
          await _edgeUpdaterOldVersions.enumerate(),
          await _autodesk.enumerate(),
          await _simulatorCaches.enumerate(),
          _system.enumerate(),
          _systemAgedSweeps.enumerate(),
          await _orphanedSystemServices.enumerate(),
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

    final failures = <String, String>{};

    // A candidate carrying a recheck must clear it immediately before its
    // own removal, regardless of mechanism — sizing every eligible
    // candidate, then waiting on the user, is exactly the window Mole
    // closes with its own second process check right before deleting.
    final byTrash = <CleanCandidate>[];
    for (final candidate in approved) {
      if (candidate.isOwnerCommand || candidate.requiresPrivilegedDeletion) {
        continue;
      }
      final failure =
          await _recheckFailure(candidate.recheckProcessGuard) ??
          await _revalidationFailure(candidate);
      if (failure != null) {
        failures[candidate.path] = failure;
      } else {
        byTrash.add(candidate);
      }
    }
    final byCommand = [
      for (final candidate in approved)
        if (candidate.isOwnerCommand) candidate,
    ];
    final byPrivilegedDelete = <CleanCandidate>[];
    for (final candidate in approved) {
      if (!candidate.requiresPrivilegedDeletion) continue;
      final failure =
          await _recheckFailure(candidate.recheckProcessGuard) ??
          await _revalidationFailure(candidate);
      if (failure != null) {
        failures[candidate.path] = failure;
      } else {
        byPrivilegedDelete.add(candidate);
      }
    }

    failures.addAll({
      ...await _trash.moveToTrash([
        for (final candidate in byTrash) candidate.path,
      ]),
      // One administrator-privileges prompt for the whole batch, not one
      // per path — approving several System items should not ask twice.
      ...await _privilegedDelete.deletePaths([
        for (final candidate in byPrivilegedDelete) candidate.path,
      ]),
    });
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

    final recheckFailure =
        await _recheckFailure(candidate.recheckProcessGuard) ??
        await _revalidationFailure(candidate);
    if (recheckFailure != null) return recheckFailure;

    final result = await _ownerCommandRunner.run(
      command.first,
      command.skip(1).toList(),
    );
    return result.isSuccess ? null : '${result.failure}';
  }

  /// Null when [recheck] is absent or confirms nothing named in it is
  /// running; otherwise a failure message. Shared by the Trash and
  /// owner-command removal paths, the only two mechanisms a
  /// [CleanCandidate.recheckProcessGuard] can attach to.
  Future<String?> _recheckFailure(ProcessRecheck? recheck) async {
    if (recheck == null) return null;
    final liveness = await _recheckGuard.check(
      exactNames: recheck.exactNames,
      patterns: recheck.patterns,
    );
    if (liveness == ProcessLiveness.notRunning) return null;
    return liveness == ProcessLiveness.running
        ? 'skipped: process started running'
        : 'skipped: process state could not be confirmed';
  }

  /// Null when [candidate] names no revalidator, or the datasource that
  /// found it still confirms it is eligible; otherwise a failure message.
  /// The scan-time check that made this candidate eligible can be stale by
  /// the time the user approves it — sizing every candidate, then waiting
  /// on the user, both happen after that check, exactly the window Mole's
  /// own pre-removal guards exist to close. A named revalidator that does
  /// not exist refuses rather than passing silently.
  Future<String?> _revalidationFailure(CleanCandidate candidate) async {
    final key = candidate.revalidatorKey;
    if (key == null) return null;
    final revalidate = _revalidators[key];
    if (revalidate == null) return 'skipped: no revalidator for "$key"';
    return await revalidate(candidate.path)
        ? null
        : 'skipped: no longer eligible';
  }

  /// Every datasource that owns a pre-removal eligibility recheck, by the
  /// key its own candidates carry.
  Map<String, Future<bool> Function(String path)> get _revalidators => {
    MacosInstallerLocalDataSource.revalidatorKey: _macosInstaller.stillEligible,
    AutodeskLocalDataSource.revalidatorKey: _autodesk.stillEligible,
    SimulatorCachesLocalDataSource.revalidatorKey:
        _simulatorCaches.stillEligible,
    OrphanedSystemServicesLocalDataSource.revalidatorKey:
        _orphanedSystemServices.stillEligible,
  };

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
