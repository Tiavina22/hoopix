import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';
import 'package:hoopix/features/purge/data/datasources/purge_identity.dart';

import '../../../support/fake_process_runner.dart';

ProcessResult _fail() =>
    ProcessResult.failure(ProcessFailure.nonZeroExit('stat', 1, ''));

void main() {
  const target = '/repo/node_modules';
  const parent = '/repo';

  test('snapshot reads both the target and its parent identity', () async {
    final identity = PurgeIdentity(
      probe: FakeProcessRunner({
        'stat -f %d:%i $parent': ProcessResult.success('16777232:100\n'),
        'stat -f %d:%i $target': ProcessResult.success('16777232:200\n'),
      }),
    );

    final snapshot = await identity.snapshot(target);

    expect(snapshot.parentIdentity, '16777232:100');
    expect(snapshot.targetIdentity, '16777232:200');
    expect(snapshot.isComplete, isTrue);
  });

  test('an unreadable half makes the snapshot incomplete', () async {
    final identity = PurgeIdentity(
      probe: FakeProcessRunner({
        'stat -f %d:%i $parent': ProcessResult.success('16777232:100\n'),
        'stat -f %d:%i $target': _fail(),
      }),
    );

    final snapshot = await identity.snapshot(target);

    expect(snapshot.isComplete, isFalse);
  });

  test('matches when nothing has changed', () async {
    final responses = {
      'stat -f %d:%i $parent': ProcessResult.success('16777232:100\n'),
      'stat -f %d:%i $target': ProcessResult.success('16777232:200\n'),
    };
    final identity = PurgeIdentity(probe: FakeProcessRunner(responses));
    final expected = await identity.snapshot(target);

    expect(await identity.matches(target, expected), isTrue);
  });

  test('does not match once the target has been replaced', () async {
    final scanTime = PurgeIdentity(
      probe: FakeProcessRunner({
        'stat -f %d:%i $parent': ProcessResult.success('16777232:100\n'),
        'stat -f %d:%i $target': ProcessResult.success('16777232:200\n'),
      }),
    );
    final expected = await scanTime.snapshot(target);

    final approvalTime = PurgeIdentity(
      probe: FakeProcessRunner({
        'stat -f %d:%i $parent': ProcessResult.success('16777232:100\n'),
        // A new inode: the old target was deleted and something else now
        // occupies the name.
        'stat -f %d:%i $target': ProcessResult.success('16777232:999\n'),
      }),
    );

    expect(await approvalTime.matches(target, expected), isFalse);
  });

  test('does not match once the parent directory has been replaced', () async {
    final scanTime = PurgeIdentity(
      probe: FakeProcessRunner({
        'stat -f %d:%i $parent': ProcessResult.success('16777232:100\n'),
        'stat -f %d:%i $target': ProcessResult.success('16777232:200\n'),
      }),
    );
    final expected = await scanTime.snapshot(target);

    final approvalTime = PurgeIdentity(
      probe: FakeProcessRunner({
        'stat -f %d:%i $parent': ProcessResult.success('16777232:555\n'),
        'stat -f %d:%i $target': ProcessResult.success('16777232:200\n'),
      }),
    );

    expect(await approvalTime.matches(target, expected), isFalse);
  });

  test('an incomplete expected snapshot never matches', () async {
    final identity = PurgeIdentity(
      probe: FakeProcessRunner({
        'stat -f %d:%i $parent': ProcessResult.success('16777232:100\n'),
        'stat -f %d:%i $target': ProcessResult.success('16777232:200\n'),
      }),
    );

    const incomplete = PurgeIdentitySnapshot(
      parentIdentity: '16777232:100',
      targetIdentity: null,
    );

    expect(await identity.matches(target, incomplete), isFalse);
  });

  test('resolves the parent of a root-level path to /', () async {
    final identity = PurgeIdentity(
      probe: FakeProcessRunner({
        'stat -f %d:%i /': ProcessResult.success('1:1\n'),
        'stat -f %d:%i /top-level': ProcessResult.success('1:2\n'),
      }),
    );

    final snapshot = await identity.snapshot('/top-level');

    expect(snapshot.isComplete, isTrue);
  });
}
