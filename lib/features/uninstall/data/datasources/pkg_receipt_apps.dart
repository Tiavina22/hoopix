import 'dart:io';

import 'package:hoopix/core/process/process_runner.dart';

/// What [PkgReceiptApps.nonstandardAppPaths] found, and whether it read
/// every receipt. An incomplete answer can still prove an install exists,
/// never that one does not.
class PkgReceiptScan {
  const PkgReceiptScan({required this.appPaths, required this.complete});

  final List<String> appPaths;
  final bool complete;
}

/// Ports `pkg_receipt_nonstandard_app_paths --require-complete`
/// (`lib/core/pkg_receipts.sh`): app bundles a package installed under
/// `/usr/local` or `/opt`, which no app-root scan reaches. Apple's own
/// receipts are skipped. Any `pkgutil` failure or a run past [deadline]
/// makes the answer incomplete.
///
/// Mole caches the result on disk for an hour, keyed by the receipt list
/// itself, so installing a package always invalidates it. hoopix keeps the
/// same key in memory for the scanner's lifetime instead, which already
/// spans every app of a batch.
class PkgReceiptApps {
  PkgReceiptApps({
    ProcessRunner? runner,
    FileSystemEntityType Function(String path)? typeOf,
  }) : _runner = runner ?? const ProcessRunner(timeout: Duration(seconds: 10)),
       _typeOf = typeOf ?? ((path) => FileSystemEntity.typeSync(path));

  final ProcessRunner _runner;
  final FileSystemEntityType Function(String path) _typeOf;

  String? _cachedReceipts;
  List<String>? _cachedApps;

  Future<PkgReceiptScan> nonstandardAppPaths({
    required DateTime deadline,
  }) async {
    final pkgs = await _runner.run('pkgutil', ['--pkgs']);
    if (!pkgs.isSuccess) {
      return const PkgReceiptScan(appPaths: [], complete: false);
    }
    final receipts = pkgs.stdout ?? '';

    if (receipts == _cachedReceipts && _cachedApps != null) {
      return PkgReceiptScan(
        appPaths: [
          for (final app in _cachedApps!)
            if (_isDirectory(app)) app,
        ],
        complete: true,
      );
    }

    final seen = <String>{};
    for (final line in receipts.split('\n')) {
      final pkgId = line.trim();
      if (pkgId.isEmpty || pkgId.startsWith('com.apple.')) continue;
      if (DateTime.now().isAfter(deadline)) {
        return PkgReceiptScan(appPaths: seen.toList(), complete: false);
      }
      final files = await _runner.run('pkgutil', ['--files', pkgId]);
      if (!files.isSuccess) {
        return PkgReceiptScan(appPaths: seen.toList(), complete: false);
      }
      for (final relative in (files.stdout ?? '').split('\n')) {
        final app = nonstandardAppFromReceiptPath(relative);
        if (app != null && _isDirectory(app)) seen.add(app);
      }
    }

    final apps = seen.toList()..sort();
    _cachedReceipts = receipts;
    _cachedApps = apps;
    return PkgReceiptScan(appPaths: apps, complete: true);
  }

  bool _isDirectory(String path) =>
      _typeOf(path) == FileSystemEntityType.directory;
}

/// The `case` in `pkg_receipt_nonstandard_app_paths`: a receipt path under
/// `/usr/local` or `/opt` that is, or lies inside, a `.app` — cut back to
/// the first `.app` in it, as `${candidate%%.app/*}.app` does. Anything
/// else is not a non-standard app install.
String? nonstandardAppFromReceiptPath(String receiptPath) {
  final stripped = receiptPath.trim().replaceFirst(RegExp('^/+'), '');
  if (stripped.isEmpty) return null;
  final candidate = '/$stripped';
  if (!candidate.startsWith('/usr/local/') && !candidate.startsWith('/opt/')) {
    return null;
  }
  final inside = candidate.indexOf('.app/');
  if (inside >= 0) return candidate.substring(0, inside + '.app'.length);
  return candidate.endsWith('.app') ? candidate : null;
}
