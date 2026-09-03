import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/datasources/host_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  test(
    'fetch falls back to "unknown" fields when probes are unavailable',
    () async {
      final runner = FakeProcessRunner(const {});

      final host = await HostLocalDataSource(runner).fetch();

      expect(host.hostname, 'unknown');
      expect(host.osVersion, 'unknown');
      expect(host.uptime, Duration.zero);
      expect(host.model, isNull);
      expect(host.chip, isNull);
    },
  );

  test('fetch reads the model and chip from system_profiler', () async {
    final runner = FakeProcessRunner({
      'system_profiler SPHardwareDataType': ProcessResult.success(
        '      Model Name: MacBook Pro\n      Chip: Apple M1\n',
      ),
    });

    final host = await HostLocalDataSource(runner).fetch();

    expect(host.model, 'MacBook Pro');
    expect(host.chip, 'Apple M1');
  });
}
