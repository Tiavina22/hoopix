import 'package:hoopix/features/status/domain/entities/bluetooth_device.dart';

class BluetoothDeviceModel extends BluetoothDevice {
  const BluetoothDeviceModel({
    required super.name,
    required super.connected,
    super.batteryLevel,
  });

  /// Parses `system_profiler SPBluetoothDataType` output.
  ///
  /// Not a port of `parseSPBluetooth` (`cmd/status/metrics_bluetooth.go`):
  /// verified against this parser's real Go logic, compiled and run
  /// against real output on a machine with both connected and
  /// disconnected accessories, every device came back `Connected: false`,
  /// including ones genuinely listed under `Connected:`. That parser looks
  /// for a per-device `Connected: Yes` detail line, which the current
  /// macOS output format never actually has — connectedness is carried
  /// entirely by which section header (`Connected:` / `Not Connected:`) a
  /// device is nested under, six spaces in:
  ///
  /// ```
  ///       Connected:
  ///           AT2Pro:
  ///               Address: 41:42:64:B1:07:73
  ///       Not Connected:
  ///           Antoinnet's JBL Go 4:
  ///               Address: 90:F2:60:D1:BE:23
  /// ```
  ///
  /// This reads that structure directly by indent instead: a line with
  /// fewer than 4 leading spaces that ends in `:` resets to the top; one
  /// with 4-7 is a section header, and its exact text is what actually
  /// carries `connected`; one with 8 or more is a device name. Mole's
  /// `bluetoothctl` fallback is not ported — that tool does not exist on
  /// macOS, so it never runs there either.
  static List<BluetoothDeviceModel> parse(String output) {
    final devices = <BluetoothDeviceModel>[];
    var sectionConnected = false;
    String? currentName;
    String? currentBattery;

    void flush() {
      final name = currentName;
      if (name != null) {
        devices.add(
          BluetoothDeviceModel(
            name: name,
            connected: sectionConnected,
            batteryLevel: currentBattery,
          ),
        );
      }
      currentName = null;
      currentBattery = null;
    }

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final indent = line.length - line.trimLeft().length;

      if (indent < 4 && trimmed.endsWith(':')) {
        flush();
        sectionConnected = false;
        continue;
      }
      if (indent >= 4 && indent < 8 && trimmed.endsWith(':')) {
        flush();
        sectionConnected = trimmed == 'Connected:';
        continue;
      }
      if (indent >= 8 && trimmed.endsWith(':')) {
        flush();
        currentName = trimmed.substring(0, trimmed.length - 1);
        continue;
      }
      if (currentName != null && trimmed.startsWith('Battery Level:')) {
        currentBattery = trimmed.substring('Battery Level:'.length).trim();
      }
    }
    flush();

    return devices;
  }
}
