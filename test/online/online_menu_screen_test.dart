import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/online/online_menu_screen.dart';

import '../helpers/test_helpers.dart';

void main() {
  setUpAll(silenceLogs);

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: OnlineMenuScreen(lobbyUrl: Uri.parse('https://lobby.example')),
    ),
  );

  testWidgets('versus offers only even team sizes', (tester) async {
    await pump(tester);
    // Untranslated keys are shown as-is without EasyLocalization loaded.
    expect(find.text('online.teamSizes.2v'), findsOneWidget);
    expect(find.text('online.teamSizes.4v'), findsOneWidget);
    expect(find.text('3'), findsNothing);

    await tester.tap(find.text('online.mode.coop'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('room codes are cleaned as typed and gate the join button', (
    tester,
  ) async {
    await pump(tester);
    // The code field sits at the bottom of the menu.
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'online.join'),
      200,
    );
    FilledButton join() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'online.join'),
    );
    expect(join().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'ab-c 2o1x9');
    await tester.pump();
    // Lower-case upper-cased; separators and look-alikes (O, 1) dropped.
    expect(find.text('ABC2X9'), findsOneWidget);
    expect(join().onPressed, isNotNull);
  });
}
