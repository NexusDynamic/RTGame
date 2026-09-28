import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:rise_together_game/src/attributes/resetable.dart';
import 'package:rise_together_game/src/services/app_logging.dart';

/// Represents a single level completion event for a team
class LevelCompletion {
  final int levelIndex;
  final double completionTime; // Seconds into the round when completed
  final double distanceAchieved;

  LevelCompletion({
    required this.levelIndex,
    required this.completionTime,
    required this.distanceAchieved,
  });

  @override
  String toString() =>
      'Level $levelIndex completed at ${completionTime.toStringAsFixed(1)}s, distance: ${distanceAchieved.toStringAsFixed(1)}m';
}

/// Represents a team's performance in a single round
class TeamRoundResult {
  final int teamId;
  final int finalLevelIndex;
  final double finalDistance;
  final List<LevelCompletion> levelsCompleted;
  final int resets;

  TeamRoundResult({
    required this.teamId,
    required this.finalLevelIndex,
    required this.finalDistance,
    required this.levelsCompleted,
    this.resets = 0,
  });

  /// Total number of levels completed in this round
  int get completedLevelCount => levelsCompleted.length;

  @override
  String toString() =>
      'Team $teamId: Level $finalLevelIndex, $completedLevelCount levels completed, final distance: ${finalDistance.toStringAsFixed(1)}m, resets: $resets';
}

/// Represents a complete round with both teams' results
class RoundResult {
  final int roundIndex;
  final double roundDuration; // Actual duration of the round in seconds
  final Map<int, TeamRoundResult> teamResults;

  /// Which trial within the round (0-based).
  final int trialIndex;

  RoundResult({
    required this.roundIndex,
    required this.roundDuration,
    required this.teamResults,
    this.trialIndex = 0,
  });

  /// Determine round winner (team that completed more levels)
  /// Returns team ID (0 or 1) or -1 for tie
  int get roundWinner {
    final team0Result = teamResults[0];
    final team1Result = teamResults[1];

    if (team0Result == null || team1Result == null) return -1;

    // First compare level index (higher level = better)
    if (team0Result.finalLevelIndex > team1Result.finalLevelIndex) return 0;
    if (team1Result.finalLevelIndex > team0Result.finalLevelIndex) return 1;

    // If same level, compare distance on that level
    if (team0Result.finalDistance > team1Result.finalDistance) return 0;
    if (team1Result.finalDistance > team0Result.finalDistance) return 1;

    return -1; // Tie
  }

  @override
  String toString() {
    final winner = roundWinner == -1 ? 'Tie' : 'Team $roundWinner wins';
    return 'Round ${roundIndex + 1}: ${teamResults.values.join(', ')} - $winner';
  }
}

/// A solo player's result
class IndividualConditionResult {
  final String playerId;
  final int finalLevelIndex;
  final double finalDistance;
  final double completionTime;

  IndividualConditionResult({
    required this.playerId,
    required this.finalLevelIndex,
    required this.finalDistance,
    required this.completionTime,
  });

  @override
  String toString() =>
      'Player $playerId: Level $finalLevelIndex, distance: ${finalDistance.toStringAsFixed(1)}m, time: ${completionTime.toStringAsFixed(1)}s';
}

/// Manages tournament progress, scoring, and state with per-team level tracking
class TournamentManager extends ChangeNotifier with AppLogging, Resetable {
  int _currentRound = 0;
  int _totalRounds = 3;
  double _roundDuration = 240.0; // Default 4 minutes per round

  /// Current seed for this tournament (used for level object placement)
  int? _currentTournamentSeed;

  /// Solo (individual) mode flag and state
  bool _isIndividualConditionMode = false;
  bool _individualConditionCompleted = false;
  IndividualConditionResult? _individualConditionResult;

  /// Solo round length in seconds; null for an untimed run.
  double? _individualConditionDuration =
      120.0; // Default 2 minutes for individual condition

  /// Per-team level tracking
  final Map<int, int> _teamLevelIndices = {
    0: 0, // Team 0 starts at level 0
    1: 0, // Team 1 starts at level 0
  };

  /// Per-team level completions in current round
  final Map<int, List<LevelCompletion>> _currentRoundCompletions = {
    0: [],
    1: [],
  };

  /// Current distances for each team (updated continuously)
  final Map<int, double> _currentTeamDistances = {0: 0.0, 1: 0.0};

  /// Reset counts for each team in current round
  final Map<int, int> _teamResets = {0: 0, 1: 0};

  /// Elapsed time in current round (seconds)
  double _currentRoundElapsedTime = 0.0;

  /// Complete round results history
  final List<RoundResult> _roundResults = [];

  // Getters
  int get currentRound => _currentRound;
  int get totalRounds => _totalRounds;
  double get roundDuration => _roundDuration;
  int? get currentTournamentSeed => _currentTournamentSeed;
  List<RoundResult> get roundResults => List.unmodifiable(_roundResults);
  Map<int, int> get teamLevelIndices => Map.unmodifiable(_teamLevelIndices);
  Map<int, double> get currentTeamDistances =>
      Map.unmodifiable(_currentTeamDistances);

  bool get isTournamentComplete => _currentRound >= _totalRounds;

  // Individual condition getters
  bool get isIndividualConditionMode => _isIndividualConditionMode;
  bool get individualConditionCompleted => _individualConditionCompleted;
  IndividualConditionResult? get individualConditionResult =>
      _individualConditionResult;
  double? get individualConditionDuration => _individualConditionDuration;

  /// Get current level index for a specific team
  int getTeamLevelIndex(int teamId) => _teamLevelIndices[teamId] ?? 0;

  /// Put a team on [levelIndex] without a completion, e.g. when a run starts
  /// part-way through the sequence.
  void setTeamLevelIndex(int teamId, int levelIndex) {
    _teamLevelIndices[teamId] = levelIndex;
    notifyListeners();
  }

  /// Get total reset count for a specific team
  int getTeamResets(int teamId) => _teamResets[teamId] ?? 0;

  /// Current round progress display
  String get roundProgress {
    if (isTournamentComplete) {
      return 'Tournament Complete!';
    }
    return 'Round ${_currentRound + 1}/$_totalRounds';
  }

  /// Tournament round wins for each team
  int get team0RoundWins =>
      _roundResults.where((r) => r.roundWinner == 0).length;
  int get team1RoundWins =>
      _roundResults.where((r) => r.roundWinner == 1).length;

  /// Initialize a new tournament
  void initialize({
    required int rounds,
    required double roundDurationSeconds,
    int? seed,
  }) {
    _totalRounds = rounds;
    _roundDuration = roundDurationSeconds;
    _currentRound = 0;
    _currentTournamentSeed = seed ?? _generateSeed();
    _roundResults.clear();
    _isIndividualConditionMode = false;
    _resetRoundState();

    appLog.info(
      'Tournament initialized: $_totalRounds rounds, ${_roundDuration}s per round, seed: $_currentTournamentSeed',
    );
    notifyListeners();
  }

  /// Generate a new random seed
  int _generateSeed() {
    return Random().nextInt(1000000);
  }

  /// Overwrite just the seed without re-initialising the tournament.
  /// Used on followers when the authority sends its seed with a level
  /// progression.
  void applySeed(int seed) {
    _currentTournamentSeed = seed;
    appLog.info('Tournament seed updated to $seed');
    notifyListeners();
  }

  /// Start a new round
  void startRound() {
    if (isTournamentComplete) {
      appLog.warning('Cannot start round: tournament already complete');
      return;
    }

    _resetRoundState();
    appLog.info('Starting round ${_currentRound + 1}');
    notifyListeners();
  }

  /// Reset state for a new round
  void _resetRoundState() {
    _teamLevelIndices[0] = 0;
    _teamLevelIndices[1] = 0;
    _currentRoundCompletions[0] = [];
    _currentRoundCompletions[1] = [];
    _currentTeamDistances[0] = 0.0;
    _currentTeamDistances[1] = 0.0;
    _currentRoundElapsedTime = 0.0;
    _teamResets[0] = 0;
    _teamResets[1] = 0;
  }

  /// Update round elapsed time
  void updateRoundTime(double elapsedSeconds) {
    _currentRoundElapsedTime = elapsedSeconds;
    notifyListeners();
  }

  /// Update the current distance for a team
  void updateTeamDistance(int teamId, double distance) {
    if (_currentTeamDistances[teamId] == null ||
        distance > _currentTeamDistances[teamId]!) {
      _currentTeamDistances[teamId] = distance;
      notifyListeners();
    }
  }

  /// Increment the reset count for a team in the current round
  void incrementTeamResets(int teamId) {
    _teamResets[teamId] = (_teamResets[teamId] ?? 0) + 1;
  }

  /// Record when a team completes a level
  void teamCompletedLevel({
    required int teamId,
    required int completedLevelIndex,
    required double distanceAchieved,
  }) {
    appLog.info(
      'Team $teamId completed level $completedLevelIndex with distance ${distanceAchieved.toStringAsFixed(1)}m at ${_currentRoundElapsedTime.toStringAsFixed(1)}s',
    );

    // Record the completion
    final completion = LevelCompletion(
      levelIndex: completedLevelIndex,
      completionTime: _currentRoundElapsedTime,
      distanceAchieved: distanceAchieved,
    );
    _currentRoundCompletions[teamId]?.add(completion);

    // Advance team to next level
    _teamLevelIndices[teamId] = completedLevelIndex + 1;

    notifyListeners();
  }

  /// Complete the current round (called when round timer expires).
  ///
  /// [roundIndex] / [trialIndex] identify the round (0-based).
  /// [authoritative] is whether this device actually simulated the round.
  /// Followers' own round timers fire too, but their level and reset counts
  /// are zero because only the authority sees completions and fatal walls, so
  /// their result is kept only for local display.
  void completeRound({
    required int roundIndex,
    int trialIndex = 0,
    bool authoritative = true,
  }) {
    if (isTournamentComplete) {
      appLog.warning('Tournament already complete, cannot complete round');
      return;
    }

    appLog.info(
      'Completing trial ${trialIndex + 1}/$_totalRounds of block $roundIndex at ${_currentRoundElapsedTime.toStringAsFixed(1)}s',
    );

    // Create team results
    final teamResults = <int, TeamRoundResult>{};
    for (final teamId in [0, 1]) {
      teamResults[teamId] = TeamRoundResult(
        teamId: teamId,
        finalLevelIndex: _teamLevelIndices[teamId] ?? 0,
        finalDistance: _currentTeamDistances[teamId] ?? 0.0,
        levelsCompleted: List.from(_currentRoundCompletions[teamId] ?? []),
        resets: _teamResets[teamId] ?? 0,
      );
    }

    // Create and store round result with explicit block/trial indices
    final roundResult = RoundResult(
      roundIndex: roundIndex,
      trialIndex: trialIndex,
      roundDuration: _currentRoundElapsedTime,
      teamResults: teamResults,
    );
    _roundResults.add(roundResult);

    appLog.info(
      'Trial completed${authoritative ? '' : ' (follower view)'}: $roundResult',
    );

    // Advance to next round
    _currentRound++;

    if (isTournamentComplete) {
      _completeTournament();
    } else {
      // Prepare for next round
      _resetRoundState();
    }

    notifyListeners();
  }

  void _completeTournament() {
    appLog.info(
      'Tournament complete! Team 0 round wins: $team0RoundWins, Team 1 round wins: $team1RoundWins',
    );
    final tournamentWinner = team0RoundWins > team1RoundWins
        ? 0
        : (team1RoundWins > team0RoundWins ? 1 : -1);
    if (tournamentWinner >= 0) {
      appLog.info('Tournament winner: Team $tournamentWinner');
    } else {
      appLog.info('Tournament ended in a tie');
    }
  }

  @override
  void reset() {
    _currentRound = 0;
    _currentTournamentSeed = _generateSeed();
    _roundResults.clear();
    _resetRoundState();

    // Reset individual condition state
    _isIndividualConditionMode = false;
    _individualConditionCompleted = false;
    _individualConditionResult = null;

    appLog.info('Tournament reset with new seed: $_currentTournamentSeed');
    notifyListeners();
  }

  /// Get a summary of the current tournament state
  String getTournamentSummary() {
    final buffer = StringBuffer();
    buffer.writeln('=== Tournament Summary ===');
    buffer.writeln(
      'Round ${_currentRound + 1}/$_totalRounds | Seed: $_currentTournamentSeed',
    );
    buffer.writeln(
      'Team 0: Level ${_teamLevelIndices[0]}, ${_currentTeamDistances[0]?.toStringAsFixed(1)}m',
    );
    buffer.writeln(
      'Team 1: Level ${_teamLevelIndices[1]}, ${_currentTeamDistances[1]?.toStringAsFixed(1)}m',
    );
    buffer.writeln(
      'Round wins: Team 0: $team0RoundWins, Team 1: $team1RoundWins',
    );
    return buffer.toString();
  }

  /// Start solo (individual) mode
  void startIndividualCondition({required double? durationSeconds, int? seed}) {
    _isIndividualConditionMode = true;
    _individualConditionCompleted = false;
    _individualConditionResult = null;
    _individualConditionDuration = durationSeconds;
    _currentTournamentSeed = seed ?? _generateSeed();
    _resetRoundState();

    appLog.info(
      'Individual condition started: ${durationSeconds ?? 'untimed'}s duration, seed: $_currentTournamentSeed',
    );
    notifyListeners();
  }

  /// Complete solo mode and record results
  void completeIndividualCondition({
    required String playerId,
    required int finalLevelIndex,
    required double finalDistance,
  }) {
    if (!_isIndividualConditionMode) {
      appLog.warning('Not in individual condition mode');
      return;
    }

    _individualConditionResult = IndividualConditionResult(
      playerId: playerId,
      finalLevelIndex: finalLevelIndex,
      finalDistance: finalDistance,
      completionTime: _currentRoundElapsedTime,
    );
    _individualConditionCompleted = true;

    appLog.info('Individual condition completed: $_individualConditionResult');
    notifyListeners();
  }

  /// Exit solo mode
  void exitIndividualCondition() {
    _isIndividualConditionMode = false;
    appLog.info('Exiting individual condition mode');
    notifyListeners();
  }
}
