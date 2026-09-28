import 'dart:async';
import 'dart:math';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:rise_together_game/src/services/app_logging.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';
import 'package:synchronized/synchronized.dart';

/// Where the player is, as far as music is concerned.
enum MusicScene {
  /// Menus, settings and matchmaking.
  lobby,

  /// A solo or online game.
  game,
}

/// Manages audio playback for the game
class AudioManager with AppLogging, AppSettings {
  static final AudioManager _instance = AudioManager._();
  static AudioManager get instance => _instance;

  AudioManager._();

  /// Background music per scene. One track loops; several play in order and
  /// then start over. An empty list means silence in that scene. Add a track
  /// by listing it here and under `assets:` in pubspec.yaml.
  static const Map<MusicScene, List<String>> musicTracks = {
    MusicScene.lobby: ['assets/audio/music/lobby.mp3'],
    MusicScene.game: ['assets/audio/music/lobby.mp3'], // for now the same track
  };

  /// Music eases in whenever it starts, since a seamless loop has no real
  /// beginning, and eases out before it stops or changes scene.
  static const Duration musicFadeIn = Duration(milliseconds: 2000);
  static const Duration musicFadeOut = Duration(milliseconds: 800);
  static const Duration _fadeStep = Duration(milliseconds: 25);

  bool _initialized = false;

  /// Whether music plays. Saved in settings; the toggles listen to this.
  late final ValueNotifier<bool> musicEnabled = ValueNotifier(
    appSettings.getBool('audio.music_enabled'),
  );

  /// Whether sound effects play. Saved in settings.
  late final ValueNotifier<bool> sfxEnabled = ValueNotifier(
    appSettings.getBool('audio.sfx_enabled'),
  );

  /// Slider positions, 0 to 1. Saved in settings.
  late final ValueNotifier<double> musicVolume = ValueNotifier(
    appSettings.getDouble('audio.music_volume'),
  );
  late final ValueNotifier<double> sfxVolume = ValueNotifier(
    appSettings.getDouble('audio.sfx_volume'),
  );

  /// Loudness is heard roughly logarithmically, so a linear gain crams all
  /// the audible change into the bottom of the slider. Squaring spreads it.
  static double _gainFor(double slider) => slider.clamp(0.0, 1.0) * slider;

  /// The music player's current volume, as last set here.
  double _musicGain = 0;

  /// Bumped by every fade; a fade that sees a newer one stops.
  int _fadeGeneration = 0;
  bool _fadingIn = false;

  /// Scenes entered and not yet left; the last one is current. The lobby is
  /// the base, entered once at startup, and game screens stack on top of it.
  final List<MusicScene> _scenes = [];

  /// What is actually playing: its scene and position in that scene's list.
  /// Tracked here rather than read from FlameAudio.bgm, so no player is
  /// created while there is no music.
  MusicScene? _playingScene;
  int _trackIndex = 0;

  /// Starting music failed, most likely a browser refusing to autoplay before
  /// the first tap. [retryMusicAfterGesture] tries again.
  bool _startFailed = false;

  final _musicLock = Lock();
  StreamSubscription<void>? _trackEnded;

  /// Initialize audio assets
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await FlameAudio.audioCache.loadAll([
        'assets/audio/sfx/hi.mp3',
        'assets/audio/sfx/lo.mp3',
      ]);
      _initialized = true;
      appLog.info('Audio assets loaded successfully');
    } catch (e) {
      appLog.severe('Failed to load audio assets: $e');
    }
  }

  Future<void> setMusicEnabled(bool enabled) async {
    musicEnabled.value = enabled;
    await appSettings.setBool('audio.music_enabled', enabled);
    await _updateMusic();
  }

  Future<void> setSfxEnabled(bool enabled) async {
    sfxEnabled.value = enabled;
    await appSettings.setBool('audio.sfx_enabled', enabled);
  }

  Future<void> setMusicVolume(double volume) async {
    musicVolume.value = volume;
    // A fade in reads the target as it goes; otherwise apply it now.
    if (_playingScene != null && !_fadingIn) {
      _musicGain = _gainFor(volume);
      try {
        await FlameAudio.bgm.audioPlayer.setVolume(_musicGain);
      } catch (e) {
        appLog.warning('Failed to set music volume: $e');
      }
    }
    await appSettings.setDouble('audio.music_volume', volume);
  }

  Future<void> setSfxVolume(double volume) async {
    sfxVolume.value = volume;
    await appSettings.setDouble('audio.sfx_volume', volume);
  }

  /// Switch to [scene]'s music. Pair every call with [leaveMusicScene], e.g.
  /// in a screen's initState and dispose.
  Future<void> enterMusicScene(MusicScene scene) async {
    _scenes.add(scene);
    await _updateMusic();
  }

  /// Leave [scene], returning to whatever was playing before it.
  Future<void> leaveMusicScene(MusicScene scene) async {
    final i = _scenes.lastIndexOf(scene);
    if (i >= 0) _scenes.removeAt(i);
    await _updateMusic();
  }

  /// Browsers only allow audio after the user has interacted with the page,
  /// so music that was refused at startup is started again from here. Cheap
  /// to call on every tap: it does nothing unless a start failed.
  Future<void> retryMusicAfterGesture() async {
    if (!_startFailed) return;
    _startFailed = false;
    _playingScene = null;
    await _updateMusic();
  }

  @visibleForTesting
  MusicScene? get wantedMusicScene => _wantedScene;

  /// The scene whose music should be playing now, or null for silence.
  MusicScene? get _wantedScene {
    if (!musicEnabled.value || _scenes.isEmpty) return null;
    final scene = _scenes.last;
    return musicTracks[scene]!.isEmpty ? null : scene;
  }

  Future<void> _updateMusic() => _musicLock.synchronized(() async {
    final scene = _wantedScene;
    if (scene == _playingScene) return;
    final previous = _playingScene;
    _playingScene = scene;
    try {
      if (previous != null) {
        await _fadeMusic(() => 0, musicFadeOut);
        await FlameAudio.bgm.stop();
      }
      if (scene == null) return;
      // Registers the lifecycle observer that pauses music in the
      // background; repeat calls are harmless.
      await FlameAudio.bgm.initialize();
      _trackEnded ??= FlameAudio.bgm.audioPlayer.onPlayerComplete.listen(
        (_) => unawaited(_nextTrack()),
      );
      _trackIndex = 0;
      await _playTrack(scene);
    } catch (e) {
      _startFailed = scene != null;
      appLog.warning('Failed to ${scene == null ? 'stop' : 'start'} music: $e');
    }
  });

  /// Start the current track silent and fade it in. Bgm loops a single file;
  /// for a list, stop at each track's end instead, and [_nextTrack] moves on.
  Future<void> _playTrack(MusicScene scene) async {
    final tracks = musicTracks[scene]!;
    _fadeGeneration++; // whatever was fading belonged to the old track
    _musicGain = 0;
    await FlameAudio.bgm.play(tracks[_trackIndex], volume: 0);
    if (tracks.length > 1) {
      await FlameAudio.bgm.audioPlayer.setReleaseMode(ReleaseMode.stop);
    }
    // Not awaited: the lock is free while the music eases in, so leaving a
    // scene straight away cancels the fade instead of waiting it out.
    unawaited(_fadeMusic(() => _gainFor(musicVolume.value), musicFadeIn));
  }

  /// Ramp the music volume to [target] over [duration]. [target] is read on
  /// every step so a volume change during a fade in is followed.
  Future<void> _fadeMusic(double Function() target, Duration duration) async {
    final generation = ++_fadeGeneration;
    final fadingIn = target() > _musicGain;
    _fadingIn = fadingIn;
    final from = _musicGain;
    final steps = max(1, duration.inMilliseconds ~/ _fadeStep.inMilliseconds);
    try {
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(_fadeStep);
        if (generation != _fadeGeneration) return;
        _musicGain = from + (target() - from) * i / steps;
        await FlameAudio.bgm.audioPlayer.setVolume(_musicGain);
      }
    } catch (e) {
      appLog.warning('Music fade failed: $e');
    } finally {
      if (generation == _fadeGeneration && fadingIn) _fadingIn = false;
    }
  }

  Future<void> _nextTrack() => _musicLock.synchronized(() async {
    final scene = _playingScene;
    if (scene == null) return;
    final tracks = musicTracks[scene]!;
    if (tracks.length < 2) return;
    _trackIndex = (_trackIndex + 1) % tracks.length;
    try {
      await _playTrack(scene);
    } catch (e) {
      appLog.warning('Failed to play the next track: $e');
    }
  });

  /// Play the "hi" sound (for "GO")
  Future<void> playHi() => _playSfx('assets/audio/sfx/hi.mp3');

  /// Play the "lo" sound (for countdown numbers)
  Future<void> playLo() => _playSfx('assets/audio/sfx/lo.mp3');

  Future<void> _playSfx(String path) async {
    if (!sfxEnabled.value) return;
    try {
      await FlameAudio.play(path, volume: _gainFor(sfxVolume.value));
    } catch (e) {
      appLog.severe('Failed to play $path: $e');
    }
  }

  /// Dispose audio resources
  void dispose() {
    FlameAudio.audioCache.clearAll();
    _initialized = false;
  }
}
