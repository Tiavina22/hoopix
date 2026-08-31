import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/status/data/models/memory_status_model.dart';

const _pageSize = 16384;
const _totalBytes = 17179869184;

// Captured from a real Apple silicon Mac.
const _vmStatFixture = '''
Mach Virtual Memory Statistics: (page size of $_pageSize bytes)
Pages free:                                     4295.
Pages active:                                 172868.
Pages inactive:                               170551.
Pages speculative:                              1762.
Pages throttled:                                   0.
Pages wired down:                             151923.
Pages purgeable:                                   2.
File-backed pages:                            129036.
Anonymous pages:                              216145.
Pages occupied by compressor:                 511289.
''';

void main() {
  test('fromVmStat counts used memory the way Activity Monitor does', () {
    final memory = MemoryStatusModel.fromVmStat(
      _vmStatFixture,
      totalBytes: _totalBytes,
    );

    const expectedUsedPages = 172868 + 151923 + 511289; // active + wired + compressed
    expect(memory.totalBytes, _totalBytes);
    expect(memory.usedBytes, expectedUsedPages * _pageSize);
    expect(memory.freeBytes, _totalBytes - expectedUsedPages * _pageSize);
  });

  test('does not count reclaimable inactive/cached pages as used', () {
    // Regression: counting everything except free+speculative reported ~99%
    // used on an idle machine, because macOS keeps inactive and file-backed
    // pages populated as cache.
    final memory = MemoryStatusModel.fromVmStat(
      _vmStatFixture,
      totalBytes: _totalBytes,
    );

    expect(memory.usedPercent, lessThan(90));
    expect(memory.freeBytes, greaterThan(0));
  });

  test('falls back to a 4096-byte page size when the header is missing', () {
    final memory = MemoryStatusModel.fromVmStat(
      'Pages active:                                     100.\n',
      totalBytes: 1000000,
    );

    expect(memory.usedBytes, 100 * 4096);
  });

  test('clamps used to the reported total', () {
    final memory = MemoryStatusModel.fromVmStat(
      _vmStatFixture,
      totalBytes: 1024,
    );

    expect(memory.usedBytes, 1024);
    expect(memory.freeBytes, 0);
  });
}
