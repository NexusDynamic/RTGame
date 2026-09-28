import 'package:easy_shared_preferences/easy_shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

mixin class AppSettings {
  EasySettings get appSettings => GlobalSettings.instance;
  static bool _isInitialized = false;
  static final _lock = Lock();

  Future<void> initSettings() async {
    await _lock.synchronized(() async {
      if (_isInitialized) return;
      _isInitialized = true;

      await GlobalSettings.initialize([
        GroupConfig(
          key: 'game',
          items: [
            /// Round duration in seconds (time limit for each round)
            DoubleSetting(key: 'round_duration', defaultValue: 180.0),

            /// Distance multiplier for converting game units to meters.
            /// World scale lives in GameGeometry.scale as a compile-time
            /// constant, because every peer must agree on it.
            DoubleSetting(key: 'distance_multiplier', defaultValue: 100.0),

            /// Number of rounds in a match
            IntSetting(key: 'tournament_rounds', defaultValue: 3),

            /// Seed for obstacle placement. 0 = a fresh random seed per match.
            IntSetting(key: 'experiment_seed', defaultValue: 0),
          ],
        ),
        GroupConfig(
          key: 'physics',
          items: [
            DoubleSetting(key: 'gravity', defaultValue: 9.81),
            DoubleSetting(key: 'paddle_width_multiplier', defaultValue: 1.7),
            DoubleSetting(key: 'thrust_multiplier', defaultValue: 0.2),
            DoubleSetting(key: 'rotation_multiplier', defaultValue: 0.3),
          ],
        ),
        GroupConfig(
          key: 'colors',
          items: [
            /// Base color for Team A
            IntSetting(key: 'team_a_color', defaultValue: 0xFF007AFF),

            /// Base color for Team B
            IntSetting(key: 'team_b_color', defaultValue: 0xFFFF9500),
          ],
        ),
        GroupConfig(
          key: 'ui',
          items: [
            /// User interface language code (e.g., 'en', 'da')
            StringSetting(key: 'language', defaultValue: 'en'),

            /// Button height as a fraction of screen height (0.0 = bottom, 1.0 = top)
            DoubleSetting(key: 'button_height', defaultValue: 0.5),

            /// Button radius
            DoubleSetting(key: 'button_radius', defaultValue: 50.0),

            /// Render the opponent inside the player's own full-screen arena
            /// as a translucent ghost, instead of in a second split-screen
            /// viewport. Read once when a game loads.
            BoolSetting(key: 'single_view_opponent', defaultValue: true),
          ],
        ),
        GroupConfig(
          key: 'audio',
          items: [
            /// Background music during games.
            BoolSetting(key: 'music_enabled', defaultValue: true),

            /// Sound effects (countdown beeps).
            BoolSetting(key: 'sfx_enabled', defaultValue: true),

            /// Slider positions, 0 to 1. AudioManager maps them to gain.
            DoubleSetting(key: 'music_volume', defaultValue: 0.7),
            DoubleSetting(key: 'sfx_volume', defaultValue: 1.0),
          ],
        ),
        GroupConfig(
          key: 'player',
          items: [
            /// Name shown to other players online.
            StringSetting(key: 'nickname', defaultValue: ''),

            /// Best solo result, for the home screen.
            IntSetting(key: 'best_solo_level', defaultValue: 0),
            DoubleSetting(key: 'best_solo_distance', defaultValue: 0.0),

            /// Highest built-in level (0-based) finished in solo; -1 = none.
            /// Unlocks starting a solo run further up.
            IntSetting(key: 'max_completed_level', defaultValue: -1),

            /// Fastest untimed runs, a JSON map of run key to seconds. See
            /// SoloProgress.
            StringSetting(key: 'best_times', defaultValue: '{}'),
          ],
        ),
        GroupConfig(
          key: 'online',
          items: [
            /// The player's own lobby server; empty = this build's default.
            /// Typed on this device, never received. See OnlineConfig.
            StringSetting(key: 'server_url', defaultValue: ''),
          ],
        ),
        GroupConfig(
          key: 'levels',
          items: [
            /// The player's own custom levels and packs, as JSON. Only ever
            /// written from this device's editor or an import the player
            /// chose; levels received online are never stored.
            StringSetting(key: 'library', defaultValue: ''),
          ],
        ),
      ]);
    });
  }
}

// Dummy class to apply the mixin and allow static initialization
class Settings with AppSettings {
  static final Settings instance = Settings._internal();

  Settings._internal();

  Future<void> initialize() async {
    await initSettings();
  }
}
