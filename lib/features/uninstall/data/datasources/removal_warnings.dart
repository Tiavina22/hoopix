import 'package:hoopix/core/process/bundle_install_resolver.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/uninstall/data/datasources/uninstall_leftover_discovery.dart';
import 'package:hoopix/features/uninstall/domain/entities/bundle_id_boundary.dart';

const _systemExtensionsRoot = '/Library/SystemExtensions';

/// Ports the two read-only checks Mole runs after a batch
/// (`lib/uninstall/batch.sh`) to warn about what an uninstall leaves behind
/// and cannot remove itself. Nothing here changes anything.
class RemovalWarnings {
  RemovalWarnings({
    ProcessRunner? runner,
    List<String> Function(String directory)? listNames,
  }) : _runner = runner ?? const ProcessRunner(timeout: Duration(seconds: 5)),
       _listNames = listNames ?? listDirectoryNames;

  final ProcessRunner _runner;
  final List<String> Function(String directory) _listNames;

  String? _uid;

  /// Ports `_uninstall_background_job_loaded`: whether any of [labels] is
  /// still loaded in the user's launchd domain. launchctl only, as in Mole:
  /// `sfltool dumpbtm` would raise an admin-password prompt on every batch,
  /// and a registered-but-unloaded Background Items record is residue macOS
  /// clears at the next login by design.
  Future<bool> backgroundJobLoaded(List<String> labels) async {
    final valid = [
      for (final label in labels)
        if (isReverseDnsBundleId(label)) label,
    ];
    if (valid.isEmpty) return false;

    final uid = _uid ??= await _readUid();
    if (uid == null) return false;

    for (final label in valid) {
      final result = await _runner.run('launchctl', [
        'print',
        'gui/$uid/$label',
      ]);
      if (result.isSuccess) return true;
    }
    return false;
  }

  Future<String?> _readUid() async {
    final result = await _runner.run('id', ['-u']);
    final uid = result.isSuccess ? result.stdout?.trim() ?? '' : '';
    return int.tryParse(uid) == null ? null : uid;
  }

  /// Mole's system extension check: a `*.systemextension` up to three
  /// levels under `/Library/SystemExtensions` whose name extends
  /// [bundleId] at a `.` boundary. macOS keeps an activated extension until
  /// it is removed in System Settings, whatever happens to its app.
  bool hasSystemExtension(String bundleId) {
    if (!isReverseDnsBundleId(bundleId)) return false;
    bool matches(String name) =>
        name.endsWith('.systemextension') &&
        nameStartsWithBundleIdBoundary(name, bundleId);

    for (final first in _listNames(_systemExtensionsRoot)) {
      if (matches(first)) return true;
      final second = '$_systemExtensionsRoot/$first';
      for (final name in _listNames(second)) {
        if (matches(name)) return true;
        for (final third in _listNames('$second/$name')) {
          if (matches(third)) return true;
        }
      }
    }
    return false;
  }
}
