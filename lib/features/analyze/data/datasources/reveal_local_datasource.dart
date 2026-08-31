import 'package:hoopix/core/process/process_runner.dart';

/// Asks Finder to select a path. `open -R` hands off to Finder over XPC and
/// returns immediately, so the default short [ProcessRunner] timeout is the
/// right one here — unlike the scan probes, which need a long one.
class RevealLocalDataSource {
  const RevealLocalDataSource(this._processRunner);

  final ProcessRunner _processRunner;

  Future<bool> reveal(String path) async {
    final result = await _processRunner.run('open', ['-R', path]);
    return result.isSuccess;
  }
}
