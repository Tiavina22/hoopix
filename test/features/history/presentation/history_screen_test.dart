import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/platform/operation_log.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/features/history/domain/entities/operation_history_entry.dart';
import 'package:hoopix/features/history/domain/repositories/history_repository.dart';
import 'package:hoopix/features/history/presentation/screens/history_screen.dart';
import 'package:hoopix/l10n/app_localizations.dart';

class _FakeHistoryRepository implements HistoryRepository {
  _FakeHistoryRepository(this.entries, {this.throwing});

  final List<OperationHistoryEntry> entries;
  final Object? throwing;
  var calls = 0;

  @override
  Future<List<OperationHistoryEntry>> recentOperations({
    int limit = 200,
  }) async {
    calls++;
    if (throwing != null) throw throwing!;
    return entries;
  }
}

Widget harness(HistoryRepository repository) => MaterialApp(
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
    body: HistoryScreen(repository: repository, homePath: '/Users/tester'),
  ),
);

void main() {
  testWidgets('shows the empty state when nothing has happened yet', (
    tester,
  ) async {
    await tester.pumpWidget(harness(_FakeHistoryRepository(const [])));
    await tester.pumpAndSettle();

    expect(find.text('No activity yet.'), findsOneWidget);
  });

  testWidgets('shows a refusal with its reason directly, the CapCut case', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      harness(
        _FakeHistoryRepository([
          OperationHistoryEntry(
            at: now,
            command: 'uninstall',
            outcome: OperationOutcome.refused,
            path: '/Applications/CapCut.app',
            detail: 'you don’t have permission to access it',
            sizeBytes: 1495638016,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('CapCut.app'), findsOneWidget);
    expect(find.text('you don’t have permission to access it'), findsOneWidget);
    expect(find.text('Refused'), findsOneWidget);
    expect(find.text('1.4 GB'), findsOneWidget);
  });

  testWidgets('groups entries under Today and Yesterday headers', (
    tester,
  ) async {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    await tester.pumpWidget(
      harness(
        _FakeHistoryRepository([
          OperationHistoryEntry(
            at: now,
            command: 'clean',
            outcome: OperationOutcome.trashed,
            path: '/today-item',
          ),
          OperationHistoryEntry(
            at: yesterday,
            command: 'clean',
            outcome: OperationOutcome.trashed,
            path: '/yesterday-item',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
  });

  testWidgets('shows the error message when reading the log fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        _FakeHistoryRepository(const [], throwing: StateError('disk error')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('disk error'), findsOneWidget);
  });

  testWidgets('the refresh button re-fetches', (tester) async {
    final repository = _FakeHistoryRepository(const []);
    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();
    expect(repository.calls, 1);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
  });
}
