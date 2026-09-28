import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/ui/server_dialog.dart';

import '../helpers/test_helpers.dart';

void main() {
  setUpAll(silenceLogs);

  /// Opens the dialog; the returned future completes with what it pops.
  Future<Future<String?>> open(
    WidgetTester tester, {
    String initial = '',
  }) async {
    late Future<String?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showDialog<String>(
              context: context,
              builder: (_) => ServerDialog(
                initial: initial,
                defaultUrl: Uri.parse('https://default.example'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  // Untranslated keys are shown as-is without EasyLocalization loaded.
  final save = find.widgetWithText(FilledButton, 'settings.server.save');

  testWidgets('rejects a bad address and saves a good one, trimmed', (
    tester,
  ) async {
    final result = await open(tester);

    await tester.enterText(find.byType(TextField), 'lobby.example');
    await tester.pump();
    expect(find.text('settings.server.invalid'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(find.byType(TextField), ' https://mine.example ');
    await tester.pump();
    expect(find.text('settings.server.invalid'), findsNothing);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(await result, 'https://mine.example');
  });

  testWidgets('use default pops an empty setting', (tester) async {
    final result = await open(tester, initial: 'https://mine.example');
    await tester.tap(find.text('settings.server.useDefault'));
    await tester.pumpAndSettle();
    expect(await result, '');
  });

  testWidgets('cancel pops null', (tester) async {
    final result = await open(tester, initial: 'https://mine.example');
    await tester.tap(find.text('settings.colors.cancel'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });
}
