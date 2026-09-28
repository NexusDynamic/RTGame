import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/editor/level_library_screen.dart';
import 'package:rise_together_game/src/online/dev_lan_screen.dart';
import 'package:rise_together_game/src/online/online_config.dart';
import 'package:rise_together_game/src/online/online_menu_screen.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:rise_together_game/src/ui/settings_screen.dart';
import 'package:rise_together_game/src/ui/solo_setup_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AppSettings {
  Future<void> _open(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    // The best score and settings may have changed.
    if (mounted) setState(() {});
  }

  /// The lobby when there is a server; the debug LAN screen when there is
  /// only a dev hub; otherwise Settings, to pick a server.
  VoidCallback _onlineAction() {
    final lobby = OnlineConfig.lobbyUrl;
    if (lobby != null) return () => _open(OnlineMenuScreen(lobbyUrl: lobby));
    if (DevLanScreen.isAvailable) return () => _open(const DevLanScreen());
    return () => _open(const SettingsScreen());
  }

  String _onlineSubtitle() {
    if (OnlineConfig.isAvailable) return 'home.onlineSubtitle'.tr();
    if (DevLanScreen.isAvailable) return 'LAN test (debug)';
    return 'home.onlineNoServer'.tr();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bestLevel = appSettings.getInt('player.best_solo_level');
    final bestDistance = appSettings.getDouble('player.best_solo_distance');
    final hasBest = bestLevel > 0 || bestDistance > 0;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Image.asset('assets/images/ball.png', height: 96),
                const SizedBox(height: 16),
                Text(
                  'app.title'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 40),
                _MenuButton(
                  icon: Icons.person,
                  title: 'home.solo'.tr(),
                  subtitle: hasBest
                      ? 'home.bestSolo'.tr(
                          args: [
                            (bestLevel + 1).toString(),
                            '${bestDistance.toStringAsFixed(1)} m',
                          ],
                        )
                      : 'home.soloSubtitle'.tr(),
                  onPressed: () async {
                    final screen = await showSoloSetupSheet(context);
                    if (screen != null) await _open(screen);
                  },
                ),
                const SizedBox(height: 12),
                _MenuButton(
                  icon: Icons.architecture,
                  title: 'home.editor'.tr(),
                  subtitle: 'home.editorSubtitle'.tr(),
                  onPressed: () => _open(const LevelLibraryScreen()),
                ),
                const SizedBox(height: 12),
                _MenuButton(
                  icon: Icons.groups,
                  title: 'home.online'.tr(),
                  subtitle: _onlineSubtitle(),
                  onPressed: _onlineAction(),
                ),
                const SizedBox(height: 12),
                _MenuButton(
                  icon: Icons.settings,
                  title: 'home.settings'.tr(),
                  onPressed: () => _open(const SettingsScreen()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.title,
    required this.onPressed,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      enabled: onPressed != null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(icon, size: 32),
      title: Text(title, style: Theme.of(context).textTheme.titleLarge),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: onPressed,
    ),
  );
}
