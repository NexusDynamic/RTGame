import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/services/app_logging.dart';
import 'package:rise_together_game/src/services/version.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:rise_together_game/src/ui/home_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

const supportedLocales = [Locale('en'), Locale('da')];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureLogging();

  await Settings.instance.initialize();
  await EasyLocalization.ensureInitialized();
  await RiseTogetherPackageInfo.instance.init();

  // Games are played hands-off for minutes at a time.
  try {
    await WakelockPlus.enable();
  } catch (e) {
    AppLogger.instance.warning('Wakelock unavailable: $e');
  }

  final language = Settings.instance.appSettings.getString('ui.language');
  runApp(
    EasyLocalization(
      supportedLocales: supportedLocales,
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: supportedLocales
          .where((l) => l.languageCode == language)
          .firstOrNull,
      child: const RiseTogetherApp(),
    ),
  );
}

/// Allows dragging with any input device (mouse, touch, trackpad).
class AnyInputScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class RiseTogetherApp extends StatelessWidget {
  const RiseTogetherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      onGenerateTitle: (_) => 'app.title'.tr(),
      debugShowCheckedModeBanner: false,
      scrollBehavior: AnyInputScrollBehavior(),
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF007AFF),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
