import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/theme/hoopix_theme.dart';
import 'package:hoopix/features/status/domain/entities/cpu_status.dart';
import 'package:hoopix/features/status/domain/entities/system_snapshot.dart';
import 'package:hoopix/features/status/domain/repositories/status_repository.dart';
import 'package:hoopix/features/status/presentation/screens/status_screen.dart';

class _FakeStatusRepository implements StatusRepository {
  @override
  Stream<SystemSnapshot> watchStatus({
    Duration interval = const Duration(seconds: 1),
  }) {
    return Stream.value(
      SystemSnapshot(
        collectedAt: DateTime(2026, 1, 1, 9, 5),
        cpu: const CpuStatus(
          userPercent: 10,
          systemPercent: 5,
          idlePercent: 85,
          physicalCores: 8,
          logicalCores: 8,
        ),
      ),
    );
  }
}

Widget _harness({ThemeData? theme}) {
  return MaterialApp(
    theme: theme,
    home: StatusScreen(repository: _FakeStatusRepository()),
  );
}

void main() {
  testWidgets('renders the snapshot from its injected repository', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_harness(theme: HoopixTheme.light()));
    await tester.pump();

    expect(find.text('Status'), findsOneWidget);
    expect(find.text('CPU'), findsOneWidget);
    // Card titles render uppercased by MetricCard.
    expect(find.text('MEMORY'), findsOneWidget);

    // Live numbers go through TabularText, which lays each digit out in its
    // own cell and publishes the whole value as one semantics label.
    expect(find.bySemanticsLabel('15%'), findsOneWidget); // 10% user + 5% sys

    semantics.dispose();
  });

  testWidgets('shows quiet placeholders for metrics that failed to collect', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(theme: HoopixTheme.light()));
    await tester.pump();

    // Memory, network, and storage are absent in the fake snapshot.
    expect(find.text('Unavailable'), findsNWidgets(3));
    expect(find.text('No battery'), findsOneWidget);
  });

  testWidgets('falls back to default palette colors without HoopixTheme', (
    tester,
  ) async {
    // A widget rendered outside HoopixTheme must degrade, not throw.
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('CPU'), findsOneWidget);
  });
}
