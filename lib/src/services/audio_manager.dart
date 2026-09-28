import 'package:flame_audio/flame_audio.dart';
import 'package:rise_together_game/src/services/app_logging.dart';

/// Manages audio playback for the game
class AudioManager with AppLogging {
  static final AudioManager _instance = AudioManager._();
  static AudioManager get instance => _instance;

  AudioManager._();

  bool _initialized = false;

  /// Initialize audio assets
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await FlameAudio.audioCache.loadAll(['sfx/hi.mp3', 'sfx/lo.mp3']);
      _initialized = true;
      appLog.info('Audio assets loaded successfully');
    } catch (e) {
      appLog.severe('Failed to load audio assets: $e');
    }
  }

  /// Play the "hi" sound (for "GO")
  Future<void> playHi() async {
    try {
      appLog.info('Playing hi sound');
      await FlameAudio.play('sfx/hi.mp3');
      appLog.info('Hi sound played successfully');
    } catch (e) {
      appLog.severe('Failed to play hi sound: $e');
    }
  }

  /// Play the "lo" sound (for countdown numbers)
  Future<void> playLo() async {
    try {
      appLog.info('Playing lo sound');
      await FlameAudio.play('sfx/lo.mp3');
      appLog.info('Lo sound played successfully');
    } catch (e) {
      appLog.severe('Failed to play lo sound: $e');
    }
  }

  /// Dispose audio resources
  void dispose() {
    FlameAudio.audioCache.clearAll();
    _initialized = false;
  }
}
