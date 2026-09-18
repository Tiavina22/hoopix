import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/features/history/domain/entities/operation_history_entry.dart';
import 'package:hoopix/features/history/domain/repositories/history_repository.dart';
import 'package:hoopix/features/history/domain/usecases/fetch_operation_history.dart';
import 'package:hoopix/features/history/presentation/state/history_controller.dart';

/// Answers each [recentOperations] call from the next entry of [answers], in
/// order; repeats the last one once exhausted.
class _FakeHistoryRepository implements HistoryRepository {
  _FakeHistoryRepository(this._answers);

  final List<Future<List<OperationHistoryEntry>> Function()> _answers;
  var _calls = 0;

  @override
  Future<List<OperationHistoryEntry>> recentOperations({int limit = 200}) {
    final index = _calls < _answers.length ? _calls : _answers.length - 1;
    _calls++;
    return _answers[index]();
  }
}

OperationHistoryEntry _entry(String path) => OperationHistoryEntry(
  at: DateTime(2026, 1, 1),
  command: 'uninstall',
  outcome: OperationOutcome.trashed,
  path: path,
);

HistoryController _controllerFor(
  List<Future<List<OperationHistoryEntry>> Function()> answers,
) => HistoryController(FetchOperationHistory(_FakeHistoryRepository(answers)));

void main() {
  test('load() populates entries and clears the loading flag', () async {
    final controller = _controllerFor([
      () async => [_entry('/A'), _entry('/B')],
    ]);

    final future = controller.load();
    expect(controller.isLoading, isTrue);
    await future;

    expect(controller.isLoading, isFalse);
    expect(controller.entries?.map((e) => e.path), ['/A', '/B']);
    expect(controller.error, isNull);
  });

  test('a failed load surfaces the error and keeps no stale entries', () async {
    final controller = _controllerFor([
      () async => throw StateError('log unreadable'),
    ]);

    await controller.load();

    expect(controller.isLoading, isFalse);
    expect(controller.error, isA<StateError>());
    expect(controller.entries, isNull);
  });

  test('refresh() re-fetches and can recover from a prior error', () async {
    final controller = _controllerFor([
      () async => throw StateError('first failed'),
      () async => [_entry('/A')],
    ]);

    await controller.load();
    expect(controller.error, isNotNull);

    await controller.refresh();

    expect(controller.error, isNull);
    expect(controller.entries?.map((e) => e.path), ['/A']);
  });
}
