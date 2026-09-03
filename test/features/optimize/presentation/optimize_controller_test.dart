import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';
import 'package:hoopix/features/optimize/domain/repositories/optimize_repository.dart';
import 'package:hoopix/features/optimize/domain/usecases/run_optimize.dart';
import 'package:hoopix/features/optimize/presentation/state/optimize_controller.dart';

const _taskA = OptimizeTask(action: 'a', name: 'A', description: 'first');
const _taskB = OptimizeTask(action: 'b', name: 'B', description: 'second');

/// Emits nothing until [finish] is called — lets a test observe controller
/// state strictly between `run()` being called and its first result.
/// [reset] re-arms it for a second `runAll()` call on the same instance.
class _GatedRepository implements OptimizeRepository {
  Completer<void> _completer = Completer<void>();

  void finish() => _completer.complete();
  void reset() => _completer = Completer<void>();

  @override
  List<OptimizeTask> get catalog => [_taskA, _taskB];

  @override
  Stream<OptimizeTaskResult> runAll() async* {
    await _completer.future;
    yield OptimizeTaskResult(task: _taskA, outcome: OptimizeOutcome.applied);
  }
}

class _FakeRepository implements OptimizeRepository {
  _FakeRepository(this._results, {this.failWith});

  final List<OptimizeTaskResult> _results;
  final Object? failWith;

  @override
  List<OptimizeTask> get catalog => [_taskA, _taskB];

  @override
  Stream<OptimizeTaskResult> runAll() async* {
    for (final result in _results) {
      yield result;
    }
    if (failWith != null) throw failWith!;
  }
}

void main() {
  test('catalog is available before a run starts', () {
    final controller = OptimizeController(
      RunOptimize(_FakeRepository(const [])),
    );

    expect(controller.catalog, [_taskA, _taskB]);
    expect(controller.results, isEmpty);
    expect(controller.isRunning, isFalse);
  });

  test(
    'run() fills in results as the stream emits, then stops running',
    () async {
      final controller = OptimizeController(
        RunOptimize(
          _FakeRepository([
            OptimizeTaskResult(task: _taskA, outcome: OptimizeOutcome.applied),
            OptimizeTaskResult(
              task: _taskB,
              outcome: OptimizeOutcome.unchanged,
            ),
          ]),
        ),
      );

      await controller.run();

      expect(controller.isRunning, isFalse);
      expect(controller.results['a']?.outcome, OptimizeOutcome.applied);
      expect(controller.results['b']?.outcome, OptimizeOutcome.unchanged);
      expect(controller.error, isNull);
    },
  );

  test('a stream error is captured rather than thrown', () async {
    final controller = OptimizeController(
      RunOptimize(
        _FakeRepository([
          OptimizeTaskResult(task: _taskA, outcome: OptimizeOutcome.applied),
        ], failWith: StateError('boom')),
      ),
    );

    await controller.run();

    expect(controller.isRunning, isFalse);
    expect(controller.error, isA<StateError>());
    // What arrived before the failure is still shown.
    expect(controller.results['a']?.outcome, OptimizeOutcome.applied);
  });

  test('results are cleared at the start of a new run', () async {
    final gate = _GatedRepository();
    final controller = OptimizeController(RunOptimize(gate));

    final first = controller.run();
    gate.finish();
    await first;
    expect(controller.results, isNotEmpty);

    gate.reset();
    final second = controller.run();
    // run() clears synchronously, before its first await — the gate has
    // not opened yet, so this observes state strictly before any new
    // result lands.
    expect(controller.results, isEmpty);

    gate.finish();
    await second;
    expect(controller.results, isNotEmpty);
  });
}
