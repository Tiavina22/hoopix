import 'dart:io';

import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/launch_service_teardown.dart';

/// The two fixed absolute paths `lsregister` has shipped at across macOS
/// releases, exactly as Mole's own `get_lsregister_path` tries them
/// (`lib/core/base.sh`).
const _lsregisterCandidates = [
  '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
  '/System/Library/CoreServices/Frameworks/LaunchServices.framework/Support/lsregister',
];

/// Ports `unregister_app_bundle` and `refresh_launch_services_after_uninstall`
/// (`lib/uninstall/batch.sh`): clears an app's stale entry from
/// LaunchServices' own database so Spotlight and Finder stop offering it,
/// then rebuilds that database once the whole batch is done.
///
/// [unregisterApp] runs per app, before its bundle moves, using the same
/// timeout-aborts-the-batch contract as [LaunchServiceTeardown.stop]: an
/// ordinary failure is ignored (an unregister that fails just leaves a
/// stale-but-harmless entry), only a timeout is worth stopping for. [refresh]
/// is whole-batch, best-effort, and never propagates a timeout — callers are
/// expected to fire it without awaiting, matching Mole's own disowned
/// background job, since a slow rebuild must never hold up the removal the
/// user is actually waiting on.
///
/// Not ported: Mole's fallback ladder that retries `-r` with fewer domains
/// when the full rebuild itself times out. hoopix's [ProcessRunner] already
/// bounds the single attempt, and losing a rebuild entirely on a slow
/// machine is an acceptable cost for work nothing else depends on.
class LaunchServicesRegistration {
  LaunchServicesRegistration({
    ProcessRunner? runner,
    ProcessRunner? refreshRunner,
    FileSystemEntityType Function(String path)? typeOf,
  }) : _runner = runner ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _refreshRunner =
           refreshRunner ?? const ProcessRunner(timeout: Duration(seconds: 15)),
       _typeOf =
           typeOf ??
           ((path) => FileSystemEntity.typeSync(path, followLinks: false));

  final ProcessRunner _runner;
  final ProcessRunner _refreshRunner;
  final FileSystemEntityType Function(String path) _typeOf;

  String? _lsregisterCached;

  String? _lsregister() {
    if (_lsregisterCached != null) return _lsregisterCached;
    for (final candidate in _lsregisterCandidates) {
      if (_typeOf(candidate) == FileSystemEntityType.file) {
        return _lsregisterCached = candidate;
      }
    }
    return null;
  }

  Future<LaunchTeardownResult> unregisterApp(String appPath) async {
    if (!appPath.endsWith('.app')) return LaunchTeardownResult.completed;
    if (_typeOf(appPath) == FileSystemEntityType.notFound) {
      return LaunchTeardownResult.completed;
    }
    final lsregister = _lsregister();
    if (lsregister == null) return LaunchTeardownResult.completed;

    final result = await _runner.run(lsregister, ['-u', appPath]);
    if (result.failure?.kind == ProcessFailureKind.timedOut) {
      return LaunchTeardownResult.timedOut;
    }
    return LaunchTeardownResult.completed;
  }

  Future<void> refresh() async {
    final lsregister = _lsregister();
    if (lsregister == null) return;
    await _refreshRunner.run(lsregister, [
      '-r',
      '-f',
      '-domain',
      'local',
      '-domain',
      'user',
      '-domain',
      'system',
    ]);
  }
}
