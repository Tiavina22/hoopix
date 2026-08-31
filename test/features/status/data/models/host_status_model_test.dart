import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/status/data/models/host_status_model.dart';

void main() {
  group('HostStatusModel.uptimeFromBoottime', () {
    test('computes uptime from a real `sysctl -n kern.boottime` line', () {
      const output = '{ sec = 1788154582, usec = 481281 } Mon Aug 31 08:36:22 2026';
      final bootTime = DateTime.fromMillisecondsSinceEpoch(1788154582 * 1000);
      final now = bootTime.add(const Duration(hours: 2));

      expect(
        HostStatusModel.uptimeFromBoottime(output, now),
        const Duration(hours: 2),
      );
    });

    test('returns zero when the line is unrecognized', () {
      expect(
        HostStatusModel.uptimeFromBoottime('garbage', DateTime.now()),
        Duration.zero,
      );
    });
  });
}
