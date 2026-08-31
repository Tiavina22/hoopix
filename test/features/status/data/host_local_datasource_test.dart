import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/status/data/datasources/host_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  test('fetch falls back to "unknown" fields when probes are unavailable', () async {
    final runner = FakeProcessRunner(const {});

    final host = await HostLocalDataSource(runner).fetch();

    expect(host.hostname, 'unknown');
    expect(host.osVersion, 'unknown');
    expect(host.uptime, Duration.zero);
  });
}
