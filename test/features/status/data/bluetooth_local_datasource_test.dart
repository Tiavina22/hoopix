import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/datasources/bluetooth_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  test('fetch parses system_profiler output into devices', () async {
    final runner = FakeProcessRunner({
      'system_profiler SPBluetoothDataType': ProcessResult.success('''
      Connected:
          AT2Pro:
              Address: 41:42:64:B1:07:73
'''),
    });

    final devices = await BluetoothLocalDataSource(runner).fetch();

    expect(devices, hasLength(1));
    expect(devices.single.name, 'AT2Pro');
    expect(devices.single.connected, isTrue);
  });

  test('fetch returns an empty list when the probe fails', () async {
    final runner = FakeProcessRunner(const {});

    final devices = await BluetoothLocalDataSource(runner).fetch();

    expect(devices, isEmpty);
  });
}
