import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/privileged_command.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelDef = MethodChannel('fit.hoopix/privileged_command');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channelDef, null);
  });

  test('returns null on success and forwards the operation and arguments', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channelDef, (call) async {
      received = call;
      return null;
    });

    final result = await const PrivilegedCommand().run(
      'reset_user_permissions',
      arguments: {'uid': '501'},
    );

    expect(result, isNull);
    expect(received?.method, 'run');
    expect(received?.arguments, {
      'operation': 'reset_user_permissions',
      'arguments': {'uid': '501'},
    });
  });

  test('sends an empty arguments map when none is given', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channelDef, (call) async {
      received = call;
      return null;
    });

    await const PrivilegedCommand().run('flush_dns');

    expect(received?.arguments, {'operation': 'flush_dns', 'arguments': {}});
  });

  test('returns the platform exception message on failure', () async {
    messenger.setMockMethodCallHandler(channelDef, (call) async {
      throw PlatformException(
        code: 'elevation_failed',
        message: 'administrator privileges were not granted',
      );
    });

    final result = await const PrivilegedCommand().run('flush_dns');

    expect(result, 'administrator privileges were not granted');
  });

  test('returns a message when no native channel is registered', () async {
    // No handler set: the messenger reports the method as unimplemented,
    // which the platform channel surfaces as MissingPluginException.
    final result = await const PrivilegedCommand().run('flush_dns');

    expect(result, isNotNull);
  });
}
