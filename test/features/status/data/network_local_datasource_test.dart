import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/datasources/network_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  test('fetch wires netstat output into a NetworkStatusModel', () async {
    final runner = FakeProcessRunner({
      'netstat -ib': ProcessResult.success(
        'Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll\n'
        'en0        1500  <Link#11>   3e:a7:c7:23:0f:59  1     0 1000  1     0 500     0\n',
      ),
    });

    final network = await NetworkLocalDataSource(runner).fetch();

    expect(network.bytesReceived, 1000);
    expect(network.bytesSent, 500);
  });

  test('fetch throws when `netstat` is unavailable', () async {
    final runner = FakeProcessRunner(const {});
    expect(NetworkLocalDataSource(runner).fetch, throwsStateError);
  });
}
