import 'package:easy_shared_preferences/easy_shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/online/online_config.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:rise_together_game/src/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_helpers.dart';

// Read lazily: settings are initialised in setUpAll.
EasySettings get settings => Settings.instance.appSettings;

void main() {
  setUpAll(() async {
    silenceLogs();
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.initialize();
  });

  setUp(() => settings.setString(OnlineConfig.settingKey, ''));

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    // Untranslated keys are shown as-is without EasyLocalization loaded.
    await tester.tap(find.text('settings.server.title'));
    await tester.pumpAndSettle();
  }

  FilledButton save(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'settings.server.save'),
  );

  testWidgets('shows the build default until a server is set', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    expect(find.text(OnlineConfig.defaultUrl.toString()), findsOneWidget);
  });

  testWidgets('rejects a bad address and saves a good one', (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField).last, 'lobby.example');
    await tester.pump();
    expect(find.text('settings.server.invalid'), findsOneWidget);
    expect(save(tester).onPressed, isNull);

    await tester.enterText(
      find.byType(TextField).last,
      ' https://mine.example ',
    );
    await tester.pump();
    expect(find.text('settings.server.invalid'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'settings.server.save'));
    await tester.pumpAndSettle();

    expect(settings.getString(OnlineConfig.settingKey), 'https://mine.example');
    expect(OnlineConfig.lobbyUrl, Uri.parse('https://mine.example'));
    expect(find.text('https://mine.example'), findsOneWidget);
  });

  testWidgets('use default clears the setting', (tester) async {
    await settings.setString(OnlineConfig.settingKey, 'https://mine.example');
    await openDialog(tester);

    await tester.tap(find.text('settings.server.useDefault'));
    await tester.pumpAndSettle();

    expect(settings.getString(OnlineConfig.settingKey), '');
    expect(OnlineConfig.lobbyUrl, OnlineConfig.defaultUrl);
  });
}
