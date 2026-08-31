import 'package:flutter_test/flutter_test.dart';
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
    });
  });
}
