import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoopix/core/navigation/shell_content_area.dart';

void main() {
  // Clean, Purge and Uninstall all confirm through a SnackBar. Before the
  // content area had a Scaffold, the app's ScaffoldMessenger had nothing to
  // present into and every confirmation ended in a failed assertion.
  testWidgets('a screen inside the shell can show a SnackBar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            const SizedBox(width: 200),
            Expanded(
              child: ShellContentArea(
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Done.'))),
                    child: const Text('Go'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Done.'), findsOneWidget);
  });
}
