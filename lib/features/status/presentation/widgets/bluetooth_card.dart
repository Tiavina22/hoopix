import 'package:flutter/material.dart';
import 'package:hoopix/core/theme/hoopix_metrics.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/core/theme/hoopix_typography.dart';
import 'package:hoopix/core/widgets/metric_card.dart';
import 'package:hoopix/features/status/domain/entities/bluetooth_device.dart';
import 'package:hoopix/l10n/app_localizations.dart';

/// Currently connected Bluetooth accessories, with battery level when
/// `system_profiler` reports one. Paired-but-not-connected devices are
/// deliberately left off: this card is about what's actionable right now
/// (a mouse or headset running low), not a full pairing list.
class BluetoothCard extends StatelessWidget {
  const BluetoothCard({super.key, required this.devices});

  final List<BluetoothDevice> devices;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final connected = [
      for (final device in devices)
        if (device.connected) device,
    ];

    return MetricCard(
      title: l10n.bluetoothCardTitle,
      child: connected.isEmpty
          ? UnavailableNote(label: l10n.noBluetoothDevicesConnected)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, device) in connected.indexed) ...[
                  if (index > 0) const SizedBox(height: HoopixSpacing.sm),
                  _DeviceRow(device: device),
                ],
              ],
            ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device});

  final BluetoothDevice device;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final battery = device.batteryLevel;

    return Text(
      battery == null
          ? device.name
          : l10n.bluetoothBatteryLevel(device.name, battery),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: HoopixType.body.copyWith(color: palette.labelPrimary),
    );
  }
}
