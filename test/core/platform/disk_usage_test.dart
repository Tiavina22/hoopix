import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/disk_usage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fit.hoopix/disk_usage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('asks the native side for every path in one call', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      // Blocks, not logical length: what a sparse file really holds.
      return <Object?>[4096, null];
    });

    final sizes = await const DiskUsage().actualSizes([
      '/a/sparse.img',
      '/a/gone.img',
    ]);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'actualSizes');
    expect(calls.single.arguments, {
      'paths': ['/a/sparse.img', '/a/gone.img'],
    });
    expect(sizes, [4096, null]);
  });

  test('no paths means no call at all', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return <Object?>[];
    });

    expect(await const DiskUsage().actualSizes([]), isEmpty);
    expect(called, isFalse);
  });

  test('falls back to logical sizes when the native side is absent', () async {
    // No mock handler registered: the channel throws MissingPluginException,
    // which is what a plain `flutter test` run sees.
    final directory = await Directory.systemTemp.createTemp('hoopix_usage_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/note.txt');
    await file.writeAsString('x' * 120);

    final sizes = await const DiskUsage().actualSizes([
      file.path,
      '${directory.path}/missing.txt',
      directory.path,
    ]);

    expect(sizes, [120, null, null]);
  });

  test('falls back when the native side answers the wrong shape', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => <Object?>[1, 2, 3],
    );

    final directory = await Directory.systemTemp.createTemp('hoopix_usage_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/note.txt');
    await file.writeAsString('x' * 7);

    // Two paths asked, three sizes returned — the answer is discarded rather
    // than lined up wrongly against the paths.
    final sizes = await const DiskUsage().actualSizes([
      file.path,
      '${directory.path}/missing.txt',
    ]);

    expect(sizes, [7, null]);
  });
}
