import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/core/platform/size_probe.dart';
import 'package:hoopix/core/platform/trash.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'dart:async';

import 'package:hoopix/features/uninstall/data/datasources/launch_service_teardown.dart';
import 'package:hoopix/features/uninstall/data/datasources/launch_services_registration.dart';
import 'package:hoopix/features/uninstall/data/datasources/live_sibling_scanner.dart';
import 'package:hoopix/features/uninstall/data/datasources/login_item_teardown.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_app_discovery.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_leftover_discovery.dart';
import 'package:hoopix/features/uninstall/domain/entities/installed_app.dart';
import 'package:hoopix/features/uninstall/domain/entities/sibling_guard.dart';
import 'package:hoopix/features/uninstall/domain/repositories/uninstall_inventory_repository.dart';

/// Sizing an app bundle is the same `du` work every other feature's own
/// size passes do.
const _sizeTimeout = Duration(seconds: 60);

class UninstallInventoryRepositoryImpl implements UninstallInventoryRepository {
  UninstallInventoryRepositoryImpl({
    required this.home,
    UninstallAppDiscovery? appDiscovery,
    UninstallLeftoverDiscovery? leftoverDiscovery,
    SizeProbe? sizeProbe,
    LiveSiblingScanner? liveSiblingScanner,
    LaunchServiceTeardown? launchServiceTeardown,
    LaunchServicesRegistration? launchServicesRegistration,
    LoginItemTeardown? loginItemTeardown,
    Trash trash = const Trash(),
    OperationLog? log,
  }) : _appDiscovery = appDiscovery ?? UninstallAppDiscovery(home: home),
       _leftoverDiscovery = leftoverDiscovery ?? UninstallLeftoverDiscovery(),
       _sizeProbe =
           sizeProbe ?? const SizeProbe(ProcessRunner(timeout: _sizeTimeout)),
       _liveSiblingScanner = liveSiblingScanner ?? LiveSiblingScanner(),
       _launchServiceTeardown =
           launchServiceTeardown ?? LaunchServiceTeardown(home: home),
       _launchServicesRegistration =
           launchServicesRegistration ?? LaunchServicesRegistration(),
       _loginItemTeardown = loginItemTeardown ?? LoginItemTeardown(),
       _trash = trash,
       _log = log ?? OperationLog(home: home);

  final String home;
  final UninstallAppDiscovery _appDiscovery;
  final UninstallLeftoverDiscovery _leftoverDiscovery;
  final SizeProbe _sizeProbe;
  final LiveSiblingScanner _liveSiblingScanner;
  final LaunchServiceTeardown _launchServiceTeardown;
  final LaunchServicesRegistration _launchServicesRegistration;
  final LoginItemTeardown _loginItemTeardown;
  final Trash _trash;
  final OperationLog _log;

  @override
  Stream<List<InstalledApp>> watchInventory() async* {
    final discovered = await _appDiscovery.discover();

    final withLeftovers = [
      for (final app in discovered)
        app.withLeftoverPaths(
          _leftoverDiscovery.discover(
            home: home,
            bundleId: app.bundleId,
            appName: app.displayName,
          ),
        ),
    ];

    yield withLeftovers;
    if (withLeftovers.isEmpty) return;

    var sizes = {for (final app in withLeftovers) app.path: app.sizeBytes};
    await for (final probe in SizeProbe.pool([
      for (final app in withLeftovers) app.path,
    ], _sizeProbe.sizeOf)) {
      sizes = {...sizes, probe.key: probe.sizeBytes};
      yield [for (final app in withLeftovers) app.withSize(sizes[app.path])];
    }
  }

  @override
  Future<Map<String, String>> approve(List<InstalledApp> approved) async {
    if (approved.isEmpty) return const {};

    // The inventory that produced [approved] can be stale by the time the
    // user confirms; a fresh snapshot is what the sibling-guard narrowing
    // below actually reasons about, matching Mole's own "never trust the
    // preview window" rule for bundle-id teardown.
    final freshInventory = await _appDiscovery.discover();

    final toRemove = <String>[];
    final sizeByPath = <String, int?>{};
    final notAttempted = <String, String>{};
    final helperIdsByApp = <String, List<String>>{};
    String? abortReason;

    for (final app in approved) {
      if (abortReason != null) {
        // launchd or LaunchServices stopped answering for an earlier app;
        // Mole abandons the rest of the batch on the same signal rather than
        // keep issuing calls that will time out too.
        notAttempted[app.path] = abortReason;
        continue;
      }

      final scanResult = await _liveSiblingScanner.scan(
        home: home,
        bundleId: app.bundleId,
        excludePath: app.path,
      );

      // A live install of the same bundle id — found, or a scan that could
      // not prove one absent — narrows to the app bundle alone: no
      // bundle-id or name-derived leftover carries the survivor's own data.
      var effectiveBundleId = 'unknown';
      var effectiveAppName = '';
      // Mole's `guard_login`: login items match by display name only, so a
      // surviving install that shares the name (or one the scan could not
      // rule out) keeps its login item.
      var removeLoginItem = false;
      // Helper ids come from the bundle and are identical across
      // same-bundle-id siblings, so only an unguarded app boots them out.
      var bootoutHelpers = false;
      if (scanResult == LiveSiblingScanResult.absent) {
        // The live scanner's own search roots are a superset of
        // UninstallAppDiscovery's, so this should already agree with
        // "absent" — kept as an independent check anyway rather than
        // trusting that the two root lists never drift apart.
        final guardLevel = siblingGuardLevelFor(
          bundleId: app.bundleId,
          appPath: app.path,
          displayName: app.displayName,
          allApps: freshInventory,
          selectedPaths: {app.path},
        );
        if (guardLevel == SiblingGuardLevel.none) {
          effectiveBundleId = app.bundleId;
          effectiveAppName = app.displayName;
          removeLoginItem = true;
          bootoutHelpers = true;
        } else if (guardLevel == SiblingGuardLevel.guard) {
          effectiveAppName = app.displayName;
          removeLoginItem = true;
        }
      }

      // Re-discover fresh rather than reusing app.leftoverPaths from the
      // stale preview — the current bundle basename is what a destructive
      // match must use, not a display name cached when the list opened.
      final leftovers = _leftoverDiscovery.discover(
        home: home,
        bundleId: effectiveBundleId,
        appName: effectiveAppName,
      );

      // Stop the app's jobs before any of its files move, as Mole's
      // `stop_launch_services` does ahead of `remove_file_list`. Uses the
      // same possibly-demoted bundle id as discovery, so a surviving
      // sibling's own agents are never unloaded by bundle id.
      final teardown = await _launchServiceTeardown.stop(
        bundleId: effectiveBundleId,
        appPath: app.path,
      );
      if (teardown == LaunchTeardownResult.timedOut) {
        abortReason = _teardownTimedOut;
        notAttempted[app.path] = abortReason;
        continue;
      }

      // Clear the app's own stale entry from LaunchServices' database while
      // its bundle still exists on disk, exactly where Mole's
      // `unregister_app_bundle` runs — right after the agent unload, still
      // ahead of the actual file move. An unregister failure other than a
      // timeout is not worth stopping for: it just leaves a harmless stale
      // entry the batch-level `refresh()` below can still clear.
      final unregister = await _launchServicesRegistration.unregisterApp(
        app.path,
      );
      if (unregister == LaunchTeardownResult.timedOut) {
        abortReason = _lsregisterTimedOut;
        notAttempted[app.path] = abortReason;
        continue;
      }

      // Same place as Mole's `remove_login_item`: after the LaunchServices
      // work, before any file moves.
      if (removeLoginItem) {
        final loginItem = await _loginItemTeardown.removeLoginItem(
          app.displayName,
        );
        if (loginItem == LaunchTeardownResult.timedOut) {
          _log.record(
            command: 'uninstall',
            outcome: OperationOutcome.skipped,
            targetPath: app.path,
            detail: _loginItemTimedOut,
          );
        }
      }

      // Read while the bundle still exists; booted out only once it is gone.
      if (bootoutHelpers) {
        helperIdsByApp[app.path] = await _loginItemTeardown.discoverHelperIds(
          app.path,
        );
      }

      toRemove.add(app.path);
      sizeByPath[app.path] = app.sizeBytes;
      for (final leftover in leftovers) {
        toRemove.add(leftover);
      }
    }

    final failures = {
      ...toRemove.isEmpty
          ? const <String, String>{}
          : await _trash.moveToTrash(toRemove),
      ...notAttempted,
    };

    // Mole boots helpers out only after the app itself was removed, so a
    // refused move never leaves a still-installed app with its helper
    // stopped.
    for (final entry in helperIdsByApp.entries) {
      if (failures.containsKey(entry.key)) continue;
      final bootout = await _loginItemTeardown.bootoutHelpers(entry.value);
      if (bootout == LaunchTeardownResult.timedOut) break;
    }

    if (toRemove.isNotEmpty) {
      // Rebuilding the whole LaunchServices database can be slow and its
      // outcome is never worth waiting on — fire it and move on, matching
      // Mole's own disowned background job, which runs after a batch that
      // actually removed something.
      unawaited(_launchServicesRegistration.refresh());
    }

    for (final path in toRemove) {
      final refusal = failures[path];
      _log.record(
        command: 'uninstall',
        outcome: refusal != null
            ? OperationOutcome.refused
            : OperationOutcome.trashed,
        targetPath: path,
        detail: refusal,
        sizeBytes: sizeByPath[path],
      );
    }

    for (final entry in notAttempted.entries) {
      _log.record(
        command: 'uninstall',
        outcome: OperationOutcome.refused,
        targetPath: entry.key,
        detail: entry.value,
        sizeBytes: sizeByPath[entry.key],
      );
    }

    return failures;
  }
}

const _teardownTimedOut =
    'launchctl did not answer in time; nothing was removed for this app';
const _lsregisterTimedOut =
    'lsregister did not answer in time; nothing was removed for this app';
const _loginItemTimedOut =
    'System Events did not answer in time; its login item was left in place';
