import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/status/data/models/network_status_model.dart';

// Trimmed from a real `netstat -ib` capture: loopback, tunnel, and virtual
// rows that must be ignored, plus en0's Link# row (counted) and its
// duplicate inet/inet6 rows for the same interface (must not double-count).
const _netstatFixture = '''
Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
lo0        16384 <Link#1>                       2119050     0 6247499865  2119050     0 6247499865     0
lo0        16384 127           localhost        2119050     - 6247499865  2119050     - 6247499865     -
gif0*      1280  <Link#2>                             0     0          0        0     0          0     0
anpi0      1500  <Link#4>    f6:94:c2:1e:83:de        0     0          0        0     0          0     0
bridge0    1500  <Link#12>   36:66:4b:95:22:00        0     0          0        0     0          0     0
en0        1500  <Link#11>   3e:a7:c7:23:0f:59  3500941     0 4587911660  2008062     0 1338183611     0
en0        1500  macs-macboo fe80:b::18ca:be3c  3500941     - 4587911660  2008062     - 1338183611     -
en0        1500  192.168.1     192.168.1.37     3500941     - 4587911660  2008062     - 1338183611     -
utun0      1380  <Link#15>                            0     0          0        2     0        200     0
''';

void main() {
  test('NetworkStatusModel.fromNetstat sums only real interfaces, once each', () {
    final network = NetworkStatusModel.fromNetstat(_netstatFixture);

    expect(network.bytesReceived, 4587911660);
    expect(network.bytesSent, 1338183611);
  });
}
