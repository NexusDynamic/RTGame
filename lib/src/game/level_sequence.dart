import 'package:rise_together_game/src/game/rise_together_levels.dart';

/// Manages an ordered sequence of levels that teams progress through.
/// Teams can be at different positions in the sequence.
class LevelSequence {
  final List<RiseTogetherLevel> _levels;

  LevelSequence(this._levels) {
    if (_levels.isEmpty) {
      throw ArgumentError('Level sequence must contain at least one level');
    }
  }

  /// Get the level at a specific index
  RiseTogetherLevel getLevelAt(int index) {
    if (index < 0) {
      throw RangeError('Level index cannot be negative: $index');
    }
    // If index is beyond last level, return the last level
    // (teams stay on final level)
    if (index >= _levels.length) {
      return _levels.last;
    }
    return _levels[index];
  }

  /// Get the total number of unique levels in the sequence
  int get levelCount => _levels.length;

  /// Check if a given index is the last level
  bool isLastLevel(int index) => index >= _levels.length - 1;

  /// Check if a given index is valid (not past the sequence)
  bool isValidIndex(int index) => index >= 0 && index < _levels.length;

  /// Get the next level index, or the current index if at the end
  int getNextLevelIndex(int currentIndex) {
    if (currentIndex < 0) {
      return 0;
    }
    if (currentIndex >= _levels.length - 1) {
      // Already at or past the last level, stay there
      return currentIndex;
    }
    return currentIndex + 1;
  }

  /// Create a default level sequence with predefined levels
  factory LevelSequence.defaultSequence() {
    return LevelSequence([
      const Level1(),
      const Level2(),
      const Level3(),
      const Level4(),
      const Level5(),
      const Level6(),
    ]);
  }

  @override
  String toString() {
    return 'LevelSequence(${_levels.length} levels)';
  }
}
