import 'dart:io';

import 'package:hoopix/core/process/process_guard.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/clean/data/datasources/clean_sections_local_datasource.dart';
import 'package:hoopix/features/clean/domain/entities/clean_plan.dart';
import 'package:hoopix/features/clean/domain/usecases/build_clean_plan.dart';

/// Proposes the process-guarded slice of `clean_cloud_storage`
/// (`lib/clean/user.sh`): Dropbox, Google Drive and OneDrive's cache
/// directories, each only while the sync client itself is confirmed not
/// running. Shares [CleanSectionsLocalDataSource.cloudAndOffice]'s section
/// name, for the same reason [BrowserProfileCachesLocalDataSource] shares
/// Browsers': the [ProcessGuard] dependency belongs in its own class.
///
/// Every one of these bundle ids is blanket-protected as a top-level
/// Caches directory (verified against `shouldProtectPath`: `com.dropbox.*`
/// and `com.getdropbox.dropbox` both match the generic `com.*`-shaped
/// filename rule's reverse-DNS check, `com.google.GoogleDrive` and
/// `com.microsoft.OneDrive` their respective vendor keywords), so
/// `userEssentials` can never clean them — this is the only way to reach
/// them, not a redundant repeat.
///
/// All three get a second guard check immediately before their own
/// removal, via [CleanSectionTargets.recheckProcessGuards] — mirrors
/// Mole's own `_clean_dropbox_caches_guarded` and the equivalent inline
/// guarded calls for Google Drive and OneDrive in `clean_cloud_storage`,
/// all of which recheck the same way right before deleting.
class CloudStorageLocalDataSource {
  CloudStorageLocalDataSource({
    required this.home,
    ProcessGuard? guard,
    Directory Function(String path)? directory,
  }) : _guard =
           guard ??
           ProcessGuard(const ProcessRunner(timeout: Duration(seconds: 5))),
       _directory = directory ?? Directory.new;

  final String home;
  final ProcessGuard _guard;
  final Directory Function(String path) _directory;

  static const _dropboxRecheck = ProcessRecheck(exactNames: ['Dropbox']);
  static const _googleDriveRecheck = ProcessRecheck(
    exactNames: ['Google Drive'],
  );
  static const _oneDriveRecheck = ProcessRecheck(exactNames: ['OneDrive']);

  Future<CleanSectionTargets> enumerate() async {
    final dropbox = await _dropboxTargets();
    final googleDrive = await _googleDriveTargets();
    final oneDrive = await _oneDriveTargets();
    return CleanSectionTargets(
      CleanSectionsLocalDataSource.cloudAndOffice,
      [...dropbox, ...googleDrive, ...oneDrive],
      recheckProcessGuards: {
        for (final path in dropbox) path: _dropboxRecheck,
        for (final path in googleDrive) path: _googleDriveRecheck,
        for (final path in oneDrive) path: _oneDriveRecheck,
      },
    );
  }

  Future<List<String>> _dropboxTargets() async {
    if (await _guard.check(exactNames: ['Dropbox']) !=
        ProcessLiveness.notRunning) {
      return const [];
    }
    return [
      '$home/Library/Caches/com.getdropbox.dropbox',
      for (final child in _childrenOf('$home/Library/Caches'))
        if (child.split('/').last.startsWith('com.dropbox.')) child,
    ];
  }

  Future<List<String>> _googleDriveTargets() async {
    if (await _guard.check(exactNames: ['Google Drive']) !=
        ProcessLiveness.notRunning) {
      return const [];
    }
    return ['$home/Library/Caches/com.google.GoogleDrive'];
  }

  Future<List<String>> _oneDriveTargets() async {
    if (await _guard.check(exactNames: ['OneDrive']) !=
        ProcessLiveness.notRunning) {
      return const [];
    }
    return ['$home/Library/Caches/com.microsoft.OneDrive'];
  }

  List<String> _childrenOf(String path) {
    try {
      return [
        for (final entity in _directory(path).listSync(followLinks: false))
          entity.path,
      ]..sort();
    } on FileSystemException {
      return const [];
    }
  }
}
