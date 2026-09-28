import 'package:flutter/foundation.dart';

/// Absolute team identifiers
enum Team {
  a(0, 'Team Alpha', 'Team A'),
  b(1, 'Team Beta', 'Team B');

  const Team(this.id, this.displayName, this.shortName);

  /// Numeric ID for array indexing and database storage
  final int id;

  /// Display name for UI
  final String displayName;

  /// Short name for compact display
  final String shortName;

  /// Get team by ID
  static Team fromId(int id) {
    return Team.values.firstWhere((team) => team.id == id);
  }

  static Team opponentOf(Team team) {
    return team.opponent;
  }

  static Team opponentOfId(int id) {
    return fromId(id).opponent;
  }

  /// Get the opposing team
  Team get opponent {
    switch (this) {
      case Team.a:
        return Team.b;
      case Team.b:
        return Team.a;
    }
  }

  @override
  String toString() => displayName;
}

/// Relative team identifiers (from current player's perspective)
enum RelativeTeam {
  mine('My Team'),
  other('Other Team');

  const RelativeTeam(this.displayName);

  final String displayName;

  /// Get the opposing relative team
  RelativeTeam get opponent {
    switch (this) {
      case RelativeTeam.mine:
        return RelativeTeam.other;
      case RelativeTeam.other:
        return RelativeTeam.mine;
    }
  }

  @override
  String toString() => displayName;
}

/// Player identification with team assignment
@immutable
class PlayerId {
  final String id;
  final Team team;
  final String? displayName;

  const PlayerId({required this.id, required this.team, this.displayName});

  /// Create a player ID with automatic display name
  const PlayerId.fromTeamAndId(this.team, this.id) : displayName = null;

  /// Get display name or fallback to ID
  String get name => displayName ?? id;

  /// Get the player's team ID for array indexing
  int get teamId => team.id;

  /// Check if this player is on the same team as another player
  bool isTeammate(PlayerId other) => team == other.team;

  /// Check if this player is on the opposing team
  bool isOpponent(PlayerId other) => team != other.team;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayerId &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          team == other.team);

  @override
  int get hashCode => Object.hash(id, team);

  @override
  String toString() => '$name (${team.shortName})';
}

/// Current player context for relative team operations
class PlayerContext extends ChangeNotifier {
  PlayerId? _currentPlayer;

  PlayerId? get currentPlayer => _currentPlayer;
  Team? get myTeam => _currentPlayer?.team;
  Team? get otherTeam => _currentPlayer?.team.opponent;

  /// Set the current player
  void setCurrentPlayer(PlayerId player) {
    if (_currentPlayer != player) {
      _currentPlayer = player;
      notifyListeners();
    }
  }

  /// Clear the current player
  void clearCurrentPlayer() {
    if (_currentPlayer != null) {
      _currentPlayer = null;
      notifyListeners();
    }
  }

  /// Convert relative team to absolute team
  Team? resolveTeam(RelativeTeam relativeTeam) {
    if (_currentPlayer == null) return null;

    switch (relativeTeam) {
      case RelativeTeam.mine:
        return _currentPlayer!.team;
      case RelativeTeam.other:
        return _currentPlayer!.team.opponent;
    }
  }

  /// Convert absolute team to relative team
  RelativeTeam? getRelativeTeam(Team team) {
    if (_currentPlayer == null) return null;

    if (team == _currentPlayer!.team) {
      return RelativeTeam.mine;
    } else {
      return RelativeTeam.other;
    }
  }

  /// Check if a team is the current player's team
  bool isMyTeam(Team team) => team == myTeam;

  /// Check if a team is the opposing team
  bool isOtherTeam(Team team) => team == otherTeam;
}
