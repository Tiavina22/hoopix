import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/status/data/datasources/memory_local_datasource.dart';

import '../../../support/fake_process_runner.dart';

void main() {
  test('fetch wires vm_stat + sysctl output into a MemoryStatusModel', () async {
    final runner = FakeProcessRunner({
      'vm_stat': ProcessResult.success(
        'Mach Virtual Memory Statistics: (page size of 16384 bytes)\n'
        'Pages free:                                     4295.\n'
        'Pages active:                                 172868.\n'
        'Pages speculative:                              1762.\n'
        'Pages wired down:                             151923.\n'
        'Pages occupied by compressor:                 511289.\n',
      ),
      'sysctl -n hw.memsize': ProcessResult.success('17179869184\n'),
    });

    final memory = await MemoryLocalDataSource(runner).fetch();

    expect(memory.totalBytes, 17179869184);
    expect(memory.usedBytes, (172868 + 151923 + 511289) * 16384);
  });

  test('fetch throws when `vm_stat` is unavailable', () async {
    final runner = FakeProcessRunner(const {});
    expect(MemoryLocalDataSource(runner).fetch, throwsStateError);
  });

  test('reads the installed memory once, not every tick', () async {
    final calls = <String>[];
    final runner = _Recording(calls, {
      'vm_stat': ProcessResult.success(
        'Mach Virtual Memory Statistics: (page size of 16384 bytes)\n',
      ),
      'sysctl -n hw.memsize': ProcessResult.success('17179869184\n'),
    });
    final source = MemoryLocalDataSource(runner);

    await source.fetch();
    final memory = await source.fetch();

    expect(memory.totalBytes, 17179869184);
    expect(calls.where((call) => call.startsWith('sysctl')), hasLength(1));
    expect(calls.where((call) => call == 'vm_stat'), hasLength(2));
  });
}

class _Recording extends FakeProcessRunner {
  _Recording(this.calls, super.responses);

  final List<String> calls;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) {
    calls.add([executable, ...arguments].join(' '));
    return super.run(executable, arguments);
  }
}
