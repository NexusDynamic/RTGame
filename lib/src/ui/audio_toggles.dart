import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:rise_together_game/src/services/audio_manager.dart';

/// Music and sound-effect toggles for the in-game screens. They share state
/// with the switches in Settings. Stacked, so they take no more width than the
/// quit button opposite them: the team distances run along the top.
class AudioToggles extends StatelessWidget {
  const AudioToggles({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = AudioManager.instance;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          ValueListenableBuilder(
            valueListenable: audio.musicEnabled,
            builder: (context, on, _) => IconButton.filledTonal(
              tooltip: (on ? 'audio.musicOff' : 'audio.musicOn').tr(),
              icon: Icon(on ? Icons.music_note : Icons.music_off),
              onPressed: () => audio.setMusicEnabled(!on),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: audio.sfxEnabled,
            builder: (context, on, _) => IconButton.filledTonal(
              tooltip: (on ? 'audio.sfxOff' : 'audio.sfxOn').tr(),
              icon: Icon(on ? Icons.volume_up : Icons.volume_off),
              onPressed: () => audio.setSfxEnabled(!on),
            ),
          ),
        ],
      ),
    );
  }
}
