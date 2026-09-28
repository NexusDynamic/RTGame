import 'package:flutter_test/flutter_test.dart';
import 'package:rise_together_game/src/services/audio_manager.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.initialize();
  });

  test('both toggles default to on', () {
    expect(AudioManager.instance.musicEnabled.value, isTrue);
    expect(AudioManager.instance.sfxEnabled.value, isTrue);
  });

  test('toggling updates the notifiers and saves the settings', () async {
    final audio = AudioManager.instance;
    final settings = Settings.instance.appSettings;

    await audio.setMusicEnabled(false);
    await audio.setSfxEnabled(false);
    expect(audio.musicEnabled.value, isFalse);
    expect(audio.sfxEnabled.value, isFalse);
    expect(settings.getBool('audio.music_enabled'), isFalse);
    expect(settings.getBool('audio.sfx_enabled'), isFalse);

    await audio.setMusicEnabled(true);
    await audio.setSfxEnabled(true);
    expect(settings.getBool('audio.music_enabled'), isTrue);
    expect(settings.getBool('audio.sfx_enabled'), isTrue);
  });

  test('volume sliders are saved', () async {
    final audio = AudioManager.instance;
    final settings = Settings.instance.appSettings;
    expect(audio.musicVolume.value, 0.7);
    expect(audio.sfxVolume.value, 1.0);

    await audio.setMusicVolume(0.3);
    await audio.setSfxVolume(0.4);
    expect(audio.musicVolume.value, 0.3);
    expect(settings.getDouble('audio.music_volume'), 0.3);
    expect(settings.getDouble('audio.sfx_volume'), 0.4);

    await audio.setMusicVolume(0.7);
    await audio.setSfxVolume(1.0);
  });

  test('game screens stack on the lobby and hand it back', () async {
    final audio = AudioManager.instance;
    // Every call below also tries to start or stop playback, which fails
    // quietly here: tests have no audio plugin. Only the choice is checked.
    await audio.enterMusicScene(MusicScene.lobby);
    expect(audio.wantedMusicScene, MusicScene.lobby);

    await audio.enterMusicScene(MusicScene.game);
    // No game tracks yet, and an empty scene is silent rather than falling
    // back to the lobby's music.
    expect(
      audio.wantedMusicScene,
      AudioManager.musicTracks[MusicScene.game]!.isEmpty
          ? null
          : MusicScene.game,
    );

    await audio.leaveMusicScene(MusicScene.game);
    expect(audio.wantedMusicScene, MusicScene.lobby);

    await audio.setMusicEnabled(false);
    expect(audio.wantedMusicScene, isNull);
    await audio.setMusicEnabled(true);
    expect(audio.wantedMusicScene, MusicScene.lobby);

    await audio.leaveMusicScene(MusicScene.lobby);
    expect(audio.wantedMusicScene, isNull);
  });
}
