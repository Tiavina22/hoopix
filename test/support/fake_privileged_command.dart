import 'package:hoopix/core/platform/privileged_command.dart';

/// Test double for [PrivilegedCommand]: returns a canned failure message
/// (or null for success) per operation id, instead of going through the
/// real platform channel. Records every call so a test can assert an
/// operation ran, or never ran (e.g. a permissions repair that skipped
/// before ever asking for elevation).
class FakePrivilegedCommand extends PrivilegedCommand {
  FakePrivilegedCommand(this._responses);

  final Map<String, String?> _responses;
  final List<String> calls = [];
  final List<Map<String, String>> argumentsByCall = [];

  @override
  Future<String?> run(
    String operation, {
    Map<String, String>? arguments,
  }) async {
    calls.add(operation);
    argumentsByCall.add(arguments ?? const {});
    if (!_responses.containsKey(operation)) {
      return 'no fake response for `$operation`';
    }
    return _responses[operation];
  }
}
