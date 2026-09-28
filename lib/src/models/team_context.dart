import 'package:flutter/material.dart';
import 'package:rise_together_game/src/game/action_system.dart';
import 'package:rise_together_game/src/models/team.dart';
import 'package:rise_together_game/src/models/team_colors.dart';
import 'package:rise_together_game/src/net/player_assignment.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';

/// Consolidated team context that handles all team-related functionality
///
/// This class centralizes team operations including:
/// - Player assignments and team membership
/// - Team colors and visual styling
/// - Display positioning (left/right)
/// - Data logging team IDs (absolute Team.a/Team.b)
class TeamContext with AppSettings {
  /// Absolute team ID for data logging and action tracking (Team.a.id or Team.b.id)
  int _teamId;

  int get teamId => _teamId;

  /// Display position - player team is always "left", opponent is "right"
  TeamDisplayPosition displayPosition;

  /// Whether this is the current player's team
  bool isPlayerTeam;

  /// Player assignments for this team
  final List<PlayerAssignment> players = [];

  final TeamActionStream actionStream;

  /// Team color scheme for visual elements
  late TeamColorPalette? _colorPalette;

  TeamContext({
    required int teamId,
    required this.displayPosition,
    required this.isPlayerTeam,
    required players,
    required this.actionStream,
    TeamColorPalette? colorPalette,
  }) : _teamId = teamId,
       _colorPalette = colorPalette {
    // Initialize color palette
    this.players.addAll(players);
    _colorPalette ??= _getDefaultColorPalette();
  }

  factory TeamContext.byPosition(
    TeamDisplayPosition position, {
    required TeamActionStream actionStream,
  }) {
    return position == TeamDisplayPosition.left
        ? TeamContext.playerTeam(actionStream: actionStream)
        : TeamContext.opponentTeam(actionStream: actionStream);
  }

  /// Create team context for player's team (always displayed on left)
  factory TeamContext.playerTeam({
    int teamId = 0,
    List<PlayerAssignment> players = const [],
    TeamColorPalette? colorPalette,
    required TeamActionStream actionStream,
  }) {
    return TeamContext(
      teamId: teamId,
      displayPosition: TeamDisplayPosition.left,
      isPlayerTeam: true,
      players: players,
      colorPalette: colorPalette,
      actionStream: actionStream,
    );
  }

  /// Create team context for opponent team (always displayed on right)
  factory TeamContext.opponentTeam({
    int teamId = 1,
    List<PlayerAssignment> players = const [],
    TeamColorPalette? colorPalette,
    required TeamActionStream actionStream,
  }) {
    return TeamContext(
      teamId: teamId,
      displayPosition: TeamDisplayPosition.right,
      isPlayerTeam: false,
      players: players,
      colorPalette: colorPalette,
      actionStream: actionStream,
    );
  }

  /// Get the absolute Team enum for data logging
  Team get absoluteTeam => Team.fromId(teamId);

  /// Get display position as string
  String get displayPositionString => displayPosition.name;

  /// Get display position as boolean (true = left, false = right)
  bool get isDisplayLeft => displayPosition == TeamDisplayPosition.left;

  /// Get team color palette
  TeamColorPalette get colorPalette =>
      _colorPalette ?? _getDefaultColorPalette();

  /// Get base team color
  Color get baseColor => colorPalette.baseColor;

  /// Get light team color
  Color get lightColor => colorPalette.lightColor;

  /// Get dark team color
  Color get darkColor => colorPalette.darkColor;

  /// Get accent team color
  Color get accentColor => colorPalette.accentColor;

  /// Get background team color
  Color get backgroundColor => colorPalette.backgroundColor;

  /// Get text team color
  Color get textColor => colorPalette.textColor;

  /// Get team color with specific opacity
  Color getColorWithOpacity(double opacity) {
    return baseColor.withValues(alpha: opacity);
  }

  /// Get number of players on this team
  int get playerCount => players.length;

  /// Get player IDs for this team
  List<String> get playerIds => players.map((p) => p.playerId).toList();

  /// Get player node IDs for this team
  List<String> get playerNodeIds => players.map((p) => p.nodeId).toList();

  /// Check if a player ID belongs to this team
  bool hasPlayer(String playerId) => playerIds.contains(playerId);

  /// Check if a player node ID belongs to this team
  bool hasPlayerNode(String nodeId) => playerNodeIds.contains(nodeId);

  /// Get team display name
  String get displayName => absoluteTeam.displayName;

  /// Get team short name
  String get shortName => absoluteTeam.shortName;

  /// Update team colors from new color palette
  TeamContext withColorPalette(TeamColorPalette newPalette) {
    return TeamContext(
      teamId: teamId,
      displayPosition: displayPosition,
      isPlayerTeam: isPlayerTeam,
      players: players,
      colorPalette: newPalette,
      actionStream: actionStream,
    );
  }

  /// Update team colors from base color
  TeamContext withBaseColor(Color newColor) {
    return withColorPalette(TeamColorPalette.fromBaseColor(newColor));
  }

  /// Update player assignments
  TeamContext withPlayers(List<PlayerAssignment> newPlayers) {
    return TeamContext(
      teamId: teamId,
      displayPosition: displayPosition,
      isPlayerTeam: isPlayerTeam,
      players: newPlayers,
      colorPalette: _colorPalette,
      actionStream: actionStream,
    );
  }

  void assign(List<PlayerAssignment> newPlayers) {
    players.clear();
    players.addAll(newPlayers);
  }

  /// Get default color palette based on absolute team ID
  TeamColorPalette _getDefaultColorPalette() {
    try {
      // Try to load from settings
      final colorKey = teamId == 0
          ? 'colors.team_a_color'
          : 'colors.team_b_color';
      final colorValue = appSettings.getInt(colorKey);
      return TeamColorPalette.fromBaseColor(Color(colorValue));
    } catch (e) {
      // Fallback to default colors
      return teamId == 0
          ? TeamColorPalette.defaultTeamA()
          : TeamColorPalette.defaultTeamB();
    }
  }

  @override
  String toString() {
    return 'TeamContext(absoluteTeam: ${absoluteTeam.shortName}, '
        'displayPosition: $displayPositionString, '
        'isPlayerTeam: $isPlayerTeam, '
        'playerCount: $playerCount)';
  }
}

/// Display position for teams (player team always left, opponent always right)
enum TeamDisplayPosition { left, right }

/// Extension to convert display position to index
extension TeamDisplayPositionExtension on TeamDisplayPosition {
  int get index {
    switch (this) {
      case TeamDisplayPosition.left:
        return 0;
      case TeamDisplayPosition.right:
        return 1;
    }
  }
}
