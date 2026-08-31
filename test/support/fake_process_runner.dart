import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';

/// Test double for [ProcessRunner]: returns canned [ProcessResult]s keyed by
/// `executable arg1 arg2 ...` instead of spawning a real process. An
/// unconfigured command returns a failure, the same as a real missing tool.
class FakeProcessRunner extends ProcessRunner {
  FakeProcessRunner(this._responses);

  final Map<String, ProcessResult> _responses;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final key = [executable, ...arguments].join(' ');
    final result = _responses[key];
    if (result == null) {
      return ProcessResult.failure(
        ProcessFailure.notFound(executable, 'no fake response for `$key`'),
      );
    }
    return result;
  }
}
