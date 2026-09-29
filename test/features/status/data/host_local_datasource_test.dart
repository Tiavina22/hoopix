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

  test('reads everything once, then only recomputes the uptime', () async {
    final runner = _Recording({
      'sysctl -n kern.boottime': ProcessResult.success(
        '{ sec = 1788154582, usec = 481281 } Mon Aug 31 08:36:22 2026\n',
      ),
      'sw_vers -productVersion': ProcessResult.success('26.0\n'),
      'hostname': ProcessResult.success('studio.local\n'),
      'system_profiler SPHardwareDataType': ProcessResult.success(
        '      Model Name: MacBook Pro\n      Chip: Apple M1\n',
      ),
    });
    final source = HostLocalDataSource(runner);

    await source.fetch();
    final callsAfterFirst = runner.calls.length;
    final host = await source.fetch();

    expect(callsAfterFirst, 4);
    expect(runner.calls, hasLength(4));
    expect(host.hostname, 'studio.local');
    expect(host.osVersion, '26.0');
    expect(host.chip, 'Apple M1');
    expect(host.uptime, greaterThan(Duration.zero));
  });

  test('a probe that failed is tried again on the next tick', () async {
    final runner = _Recording(const {});
    final source = HostLocalDataSource(runner);

    await source.fetch();
    await source.fetch();

    expect(
      runner.calls.where(
        (call) => call == 'system_profiler SPHardwareDataType',
      ),
      hasLength(2),
    );
  });
}

class _Recording extends FakeProcessRunner {
  _Recording(super.responses);

  final calls = <String>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) {
    calls.add([executable, ...arguments].join(' '));
    return super.run(executable, arguments);
  }
}
