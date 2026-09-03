import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/status/data/models/bluetooth_device_model.dart';

void main() {
  group('BluetoothDeviceModel.parse', () {
    test('reads connected and not-connected devices from their section', () {
      const output = '''
Bluetooth:

      Bluetooth Controller:
          Address: 3C:06:30:42:CE:0E
          State: On
      Connected:
          AT2Pro:
              Address: 41:42:64:B1:07:73
              Minor Type: Headset
      Not Connected:
          Antoinnet's JBL Go 4:
              Address: 90:F2:60:D1:BE:23
              Minor Type: Speaker
''';

      final devices = BluetoothDeviceModel.parse(output);

      expect(devices, hasLength(2));
      expect(devices[0].name, 'AT2Pro');
      expect(devices[0].connected, isTrue);
      expect(devices[1].name, "Antoinnet's JBL Go 4");
      expect(devices[1].connected, isFalse);
    });

    test('reads a battery level nested under a connected device', () {
      const output = '''
      Connected:
          Magic Mouse:
              Address: 00:00:00:00:00:00
              Battery Level: 80%
''';

      final devices = BluetoothDeviceModel.parse(output);

      expect(devices.single.name, 'Magic Mouse');
      expect(devices.single.connected, isTrue);
      expect(devices.single.batteryLevel, '80%');
    });

    test('a device with no Battery Level line has a null batteryLevel', () {
      const output = '''
      Connected:
          AT2Pro:
              Address: 41:42:64:B1:07:73
''';

      final devices = BluetoothDeviceModel.parse(output);

      expect(devices.single.batteryLevel, isNull);
    });

    test('returns an empty list for output with no devices at all', () {
      const output = '''
Bluetooth:

      Bluetooth Controller:
          Address: 3C:06:30:42:CE:0E
          State: On
''';

      expect(BluetoothDeviceModel.parse(output), isEmpty);
    });

    test('returns an empty list for unrecognized output', () {
      expect(BluetoothDeviceModel.parse('garbage'), isEmpty);
    });

    test('a top-level reset does not leak a connected state into the next '
        'top-level block', () {
      const output = '''
Bluetooth:

      Connected:
          First:
              Address: 00:00:00:00:00:01

Some Other Top Level Block:

      Not Connected:
          Second:
              Address: 00:00:00:00:00:02
''';

      final devices = BluetoothDeviceModel.parse(output);

      final first = devices.firstWhere((d) => d.name == 'First');
      final second = devices.firstWhere((d) => d.name == 'Second');
      expect(first.connected, isTrue);
      expect(second.connected, isFalse);
    });
  });
}
