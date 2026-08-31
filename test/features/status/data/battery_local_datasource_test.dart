import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/datasources/battery_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  test('fetch returns null when the Mac has no battery', () async {
    final runner = FakeProcessRunner({
      'pmset -g batt': ProcessResult.success("Now drawing from 'AC Power'\n"),
    });

    expect(await BatteryLocalDataSource(runner).fetch(), isNull);
  });

  test('fetch returns null (not a throw) when the probe is unavailable', () async {
    final runner = FakeProcessRunner(const {});
    expect(await BatteryLocalDataSource(runner).fetch(), isNull);
  });
}
