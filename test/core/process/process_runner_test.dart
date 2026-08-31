import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/process/process_failure.dart';
import 'package:hoopix/core/process/process_runner.dart';

void main() {
  group('ProcessRunner', () {
    test('returns stdout on success', () async {
      final result = await const ProcessRunner().run('echo', ['hello']);

      expect(result.isSuccess, isTrue);
      expect(result.stdout, 'hello\n');
    });

    test('fails with a typed reason when the executable does not exist', () async {
      final result = await const ProcessRunner().run(
        'hoopix-does-not-exist-binary',
        const [],
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure.toString(), contains('not found'));
    });

    test('times out instead of hanging on a slow command', () async {
      final runner = const ProcessRunner(timeout: Duration(milliseconds: 100));

      final result = await runner.run('sleep', ['5']);

      expect(result.isSuccess, isFalse);
      expect(result.failure.toString(), contains('timed out'));
    });

    test('reports a non-zero exit code', () async {
      final result = await const ProcessRunner().run('false', const []);

      expect(result.isSuccess, isFalse);
      expect(result.failure.toString(), contains('exited'));
      expect(result.failure!.kind, ProcessFailureKind.nonZeroExit);
    });

    // `du` exits non-zero as soon as any descendant is unreadable while
    // still printing a usable total, so a failed run's stdout has to survive.
    test('keeps stdout when the command exits non-zero', () async {
      final result = await const ProcessRunner().run('sh', [
        '-c',
        'echo partial; exit 1',
      ]);

      expect(result.isSuccess, isFalse);
      expect(result.stdout, 'partial\n');
      expect(result.failure!.kind, ProcessFailureKind.nonZeroExit);
    });

    test('carries no stdout when it timed out', () async {
      const runner = ProcessRunner(timeout: Duration(milliseconds: 100));

      final result = await runner.run('sleep', ['5']);

      expect(result.stdout, isNull);
      expect(result.failure!.kind, ProcessFailureKind.timedOut);
    });
  });
}
