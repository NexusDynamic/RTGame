import 'package:easy_localization/easy_localization.dart';
import 'package:easy_shared_preferences/easy_shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:rise_together_game/src/services/audio_manager.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';

/// Player-facing settings. Changes are saved as they are made.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with AppSettings {
  late final TextEditingController _nickname = TextEditingController(
    text: appSettings.getString('player.nickname'),
  );

  static const _roundDurations = [60.0, 120.0, 180.0, 240.0, 300.0];

  static const _teamColors = [
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.brown,
  ];

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _set(Future<void> Function() write) async {
    await write();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final roundDuration = appSettings.getDouble('game.round_duration');
    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr())),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _Section('settings.sections.player'.tr()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _nickname,
              maxLength: 16,
              decoration: InputDecoration(
                labelText: 'settings.nickname.title'.tr(),
                helperText: 'settings.nickname.hint'.tr(),
              ),
              onChanged: (value) =>
                  appSettings.setString('player.nickname', value.trim()),
            ),
          ),
          _Section('settings.sections.game'.tr()),
          ListTile(
            title: Text('settings.roundDuration.title'.tr()),
            trailing: DropdownButton<double>(
              value: _roundDurations.contains(roundDuration)
                  ? roundDuration
                  : null,
              items: [
                for (final seconds in _roundDurations)
                  DropdownMenuItem(
                    value: seconds,
                    child: Text(
                      'settings.roundDuration.value'.tr(
                        args: [seconds.toInt().toString()],
                      ),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                _set(() => appSettings.setDouble('game.round_duration', value));
              },
            ),
          ),
          _Section('settings.sections.audio'.tr()),
          ValueListenableBuilder(
            valueListenable: AudioManager.instance.musicEnabled,
            builder: (context, on, _) => SwitchListTile(
              title: Text('settings.music.title'.tr()),
              subtitle: Text('settings.music.description'.tr()),
              value: on,
              onChanged: AudioManager.instance.setMusicEnabled,
            ),
          ),
          ValueListenableBuilder(
            valueListenable: AudioManager.instance.musicVolume,
            builder: (context, volume, _) => _SliderTile(
              title: 'settings.musicVolume'.tr(),
              value: volume,
              min: 0,
              max: 1,
              onChanged: AudioManager.instance.setMusicVolume,
            ),
          ),
          ValueListenableBuilder(
            valueListenable: AudioManager.instance.sfxEnabled,
            builder: (context, on, _) => SwitchListTile(
              title: Text('settings.sfx.title'.tr()),
              subtitle: Text('settings.sfx.description'.tr()),
              value: on,
              onChanged: AudioManager.instance.setSfxEnabled,
            ),
          ),
          ValueListenableBuilder(
            valueListenable: AudioManager.instance.sfxVolume,
            builder: (context, volume, _) => _SliderTile(
              title: 'settings.sfxVolume'.tr(),
              value: volume,
              min: 0,
              max: 1,
              onChanged: AudioManager.instance.setSfxVolume,
            ),
          ),
          _Section('settings.sections.display'.tr()),
          SwitchListTile(
            title: Text('settings.singleView.title'.tr()),
            subtitle: Text('settings.singleView.description'.tr()),
            value: appSettings.getBool('ui.single_view_opponent'),
            onChanged: (value) => _set(
              () => appSettings.setBool('ui.single_view_opponent', value),
            ),
          ),
          _SliderTile(
            title: 'settings.buttonHeight.title'.tr(),
            subtitle: 'settings.buttonHeight.description'.tr(),
            value: appSettings.getDouble('ui.button_height'),
            min: 0.2,
            max: 0.9,
            onChanged: (value) =>
                _set(() => appSettings.setDouble('ui.button_height', value)),
          ),
          _SliderTile(
            title: 'settings.buttonSize.title'.tr(),
            value: appSettings.getDouble('ui.button_radius'),
            min: 30,
            max: 90,
            onChanged: (value) =>
                _set(() => appSettings.setDouble('ui.button_radius', value)),
          ),
          _Section('settings.sections.colors'.tr()),
          _colorTile('settings.colors.teamA'.tr(), 'colors.team_a_color'),
          _colorTile('settings.colors.teamB'.tr(), 'colors.team_b_color'),
          _Section('settings.sections.language'.tr()),
          RadioGroup<String>(
            groupValue: context.locale.languageCode,
            onChanged: (code) async {
              if (code == null) return;
              await context.setLocale(Locale(code));
              await _set(() => appSettings.setString('ui.language', code));
            },
            child: const Column(
              children: [
                RadioListTile(value: 'en', title: Text('English')),
                RadioListTile(value: 'da', title: Text('Dansk')),
              ],
            ),
          ),
          const Divider(),
          Center(
            child: TextButton(
              onPressed: () async {
                for (final group in const ['game', 'ui', 'colors']) {
                  await GlobalSettings.resetGroup(group);
                }
                if (mounted) setState(() {});
              },
              child: Text('settings.resetDefaults'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorTile(String team, String key) {
    final color = Color(appSettings.getInt(key));
    return ListTile(
      title: Text(team),
      trailing: GestureDetector(
        onTap: () => _pickColor(team, key, color),
        child: Container(
          width: 40,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white38, width: 2),
          ),
        ),
      ),
      onTap: () => _pickColor(team, key, color),
    );
  }

  Future<void> _pickColor(String team, String key, Color current) async {
    var selected = current;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings.colors.pickerTitle'.tr(args: [team])),
        content: SizedBox(
          width: 300,
          child: BlockPicker(
            pickerColor: current,
            availableColors: _teamColors,
            onColorChanged: (color) => selected = color,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('settings.colors.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('settings.colors.select'.tr()),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _set(() => appSettings.setInt(key, selected.toARGB32()));
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subtitle != null) Text(subtitle!),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}
