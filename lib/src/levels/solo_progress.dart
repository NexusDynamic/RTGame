import 'dart:convert';

import 'package:rise_together_game/src/settings/app_settings.dart';

/// What solo play has unlocked and the best untimed times, kept in settings.
class SoloProgress with AppSettings {
  /// Levels in the built-in sequence.
  static const builtInLevelCount = 10;

  static const _maxTimes = 200;

  /// Highest built-in level finished, 0-based; -1 when none.
  int get maxCompletedLevel {
    final stored = appSettings.getInt('player.max_completed_level');
    // Older installs only have the best level *reached*: everything below it
    // was finished.
    final fromBest = appSettings.getInt('player.best_solo_level') - 1;
    return (stored > fromBest ? stored : fromBest).clamp(
      -1,
      builtInLevelCount - 1,
    );
  }

  /// How many built-in levels a run may start at: every finished level, and
  /// the first one not yet finished.
  int get startableLevelCount =>
      (maxCompletedLevel + 2).clamp(1, builtInLevelCount);

  Future<void> recordCompleted(int levelIndex) async {
    if (levelIndex <= maxCompletedLevel) return;
    await appSettings.setInt(
      'player.max_completed_level',
      levelIndex.clamp(0, builtInLevelCount - 1),
    );
  }

  /// Run key for the best-time table.
  static String builtInRunKey(int startLevelIndex) =>
      'default:$startLevelIndex';
  static String customRunKey(String packId) => 'custom:$packId';

  Map<String, double> _times() {
    try {
      final decoded = jsonDecode(appSettings.getString('player.best_times'));
      if (decoded is! Map<String, dynamic>) return {};
      return {
        for (final MapEntry(:key, :value) in decoded.entries)
          if (value is num && value.isFinite && value > 0)
            key: value.toDouble(),
      };
    } on FormatException {
      return {};
    }
  }

  double? bestTime(String runKey) => _times()[runKey];

  /// Store [seconds] if it beats the previous best. Returns whether it did.
  Future<bool> recordTime(String runKey, double seconds) async {
    final times = _times();
    final previous = times[runKey];
    if (previous != null && previous <= seconds) return false;
    if (previous == null && times.length >= _maxTimes) return false;
    times[runKey] = seconds;
    await appSettings.setString('player.best_times', jsonEncode(times));
    return true;
  }
}
