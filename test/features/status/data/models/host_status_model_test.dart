import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/status/data/models/host_status_model.dart';

void main() {
  group('HostStatusModel.uptimeFromBoottime', () {
    test('computes uptime from a real `sysctl -n kern.boottime` line', () {
      const output =
          '{ sec = 1788154582, usec = 481281 } Mon Aug 31 08:36:22 2026';
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

  group('HostStatusModel.parseHardwareInfo', () {
    test('reads the model name and Apple Silicon chip', () {
      const output = '''
Hardware:

    Hardware Overview:

      Model Name: MacBook Pro
      Model Identifier: MacBookPro17,1
      Chip: Apple M1
      Total Number of Cores: 8 (4 Performance and 4 Efficiency)
      Memory: 16 GB
''';

      final result = HostStatusModel.parseHardwareInfo(output);

      expect(result.model, 'MacBook Pro');
      expect(result.chip, 'Apple M1');
    });

    test('falls back to Processor Name on an Intel Mac with no Chip line', () {
      const output = '''
      Model Name: MacBook Pro
      Processor Name: Quad-Core Intel Core i7
      Processor Speed: 2.8 GHz
''';

      final result = HostStatusModel.parseHardwareInfo(output);

      expect(result.model, 'MacBook Pro');
      expect(result.chip, 'Quad-Core Intel Core i7');
    });

    test('prefers Chip over Processor Name when both are present', () {
      const output = '''
      Chip: Apple M1
      Processor Name: should not win
''';

      final result = HostStatusModel.parseHardwareInfo(output);

      expect(result.chip, 'Apple M1');
    });

    test('skips a line with more than one colon', () {
      const output = '''
      Model Name: Mac: Pro
      Chip: Apple M1
''';

      final result = HostStatusModel.parseHardwareInfo(output);

      expect(result.model, isNull);
      expect(result.chip, 'Apple M1');
    });

    test('returns nulls for output with neither field', () {
      final result = HostStatusModel.parseHardwareInfo('nothing useful here');

      expect(result.model, isNull);
      expect(result.chip, isNull);
    });
  });
}
