/// One paired Bluetooth accessory, from `system_profiler SPBluetoothDataType`.
class BluetoothDevice {
  const BluetoothDevice({
    required this.name,
    required this.connected,
    this.batteryLevel,
  });

  final String name;
  final bool connected;

  /// The device's own reported charge, e.g. "80%". Null when
  /// `system_profiler` has no `Battery Level:` line for it — most
  /// accessories other than a mouse, keyboard, trackpad, or headset with
  /// battery reporting never do.
  final String? batteryLevel;
}
