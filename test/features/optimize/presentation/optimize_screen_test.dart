import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_outcome.dart';
import 'package:hoopix/features/optimize/domain/entities/optimize_task.dart';
import 'package:hoopix/features/optimize/domain/repositories/optimize_repository.dart';
import 'package:hoopix/features/optimize/presentation/screens/optimize_screen.dart';
import 'package:hoopix/l10n/app_localizations.dart';

const _taskA = OptimizeTask(
  action: 'a',
  name: 'Task A',
  description: 'Does the first thing',
);
const _taskB = OptimizeTask(
  action: 'b',
  name: 'Task B',
  description: 'Does the second thing',
);

class _FakeOptimizeRepository implements OptimizeRepository {
  _FakeOptimizeRepository(this.results);

  final List<OptimizeTaskResult> results;

  @override
  List<OptimizeTask> get catalog => [_taskA, _taskB];

  @override
  Stream<OptimizeTaskResult> runAll() => Stream.fromIterable(results);
}

Widget harness(OptimizeRepository repository) => MaterialApp(
  theme: HoopixTheme.light(),
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: OptimizeScreen(repository: repository, homePath: '/Users/tester'),
  ),
);

void main() {
  testWidgets('shows the catalog before anything has run', (tester) async {
    await tester.pumpWidget(harness(_FakeOptimizeRepository(const [])));
    await tester.pumpAndSettle();

    expect(find.text('Task A'), findsOneWidget);
    expect(find.text('Does the first thing'), findsOneWidget);
    expect(find.text('Task B'), findsOneWidget);
    expect(find.text('Run Maintenance'), findsOneWidget);
  });

  testWidgets('running fills in each task\'s outcome', (tester) async {
    await tester.pumpWidget(
      harness(
        _FakeOptimizeRepository([
          const OptimizeTaskResult(
            task: _taskA,
            outcome: OptimizeOutcome.applied,
          ),
          const OptimizeTaskResult(
            task: _taskB,
            outcome: OptimizeOutcome.unchanged,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run Maintenance'));
    await tester.pumpAndSettle();

    expect(find.text('Applied'), findsOneWidget);
    expect(find.text('Already optimal'), findsOneWidget);
  });
}
