import 'package:flutter/material.dart';
import 'package:rise_together_game/src/models/team.dart';

/// Team color palette with different shades and variations for Material design
class TeamColorPalette {
  final Color baseColor;
  final Color lightColor;
  final Color darkColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color textColor;

  const TeamColorPalette({
    required this.baseColor,
    required this.lightColor,
    required this.darkColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.textColor,
  });

  /// Create a palette from a base color
  factory TeamColorPalette.fromBaseColor(Color baseColor) {
    final hsv = HSVColor.fromColor(baseColor);

    return TeamColorPalette(
      baseColor: baseColor,
      lightColor: hsv
          .withSaturation((hsv.saturation * 0.6).clamp(0.0, 1.0))
          .withValue((hsv.value * 1.15).clamp(0.0, 1.0))
          .toColor(),
      darkColor: hsv
          .withValue((hsv.value * 0.75).clamp(0.0, 1.0))
          .withSaturation((hsv.saturation * 1.1).clamp(0.0, 1.0))
          .toColor(),
      accentColor: hsv
          .withHue((hsv.hue + 25) % 360)
          .withSaturation((hsv.saturation * 0.9).clamp(0.0, 1.0))
          .toColor(),
      backgroundColor: hsv
          .withSaturation((hsv.saturation * 0.25).clamp(0.0, 1.0))
          .withValue((hsv.value * 0.95).clamp(0.0, 1.0))
          .toColor()
          .withValues(alpha: 0.15),
      textColor: hsv.value > 0.6 ? Colors.black : Colors.white,
    );
  }

  /// Create default palette for Team A (blue-based, iOS style)
  factory TeamColorPalette.defaultTeamA() {
    return TeamColorPalette.fromBaseColor(Colors.blue);
  }

  /// Create default palette for Team B (orange-based, iOS style)
  factory TeamColorPalette.defaultTeamB() {
    return TeamColorPalette.fromBaseColor(Colors.orange);
  }

  /// Get color with specified alpha
  Color withAlpha(Color color, double alpha) {
    return color.withValues(alpha: alpha);
  }
}

/// Manages team color schemes and provides color access
class TeamColorScheme {
  final Map<Team, TeamColorPalette> _teamPalettes;

  TeamColorScheme(this._teamPalettes);

  /// Create default color scheme with Material design colors
  factory TeamColorScheme.defaultScheme() {
    return TeamColorScheme({
      Team.a: TeamColorPalette.defaultTeamA(),
      Team.b: TeamColorPalette.defaultTeamB(),
    });
  }

  /// Create color scheme from base colors
  factory TeamColorScheme.fromBaseColors({
    required Color teamAColor,
    required Color teamBColor,
  }) {
    return TeamColorScheme({
      Team.a: TeamColorPalette.fromBaseColor(teamAColor),
      Team.b: TeamColorPalette.fromBaseColor(teamBColor),
    });
  }

  /// Get palette for a team
  TeamColorPalette getPalette(Team team) {
    return _teamPalettes[team] ?? TeamColorPalette.defaultTeamA();
  }

  /// Get base color for a team
  Color getBaseColor(Team team) => getPalette(team).baseColor;

  /// Get light color for a team
  Color getLightColor(Team team) => getPalette(team).lightColor;

  /// Get dark color for a team
  Color getDarkColor(Team team) => getPalette(team).darkColor;

  /// Get accent color for a team
  Color getAccentColor(Team team) => getPalette(team).accentColor;

  /// Get background color for a team
  Color getBackgroundColor(Team team) => getPalette(team).backgroundColor;

  /// Get text color for a team
  Color getTextColor(Team team) => getPalette(team).textColor;

  /// Get color with specific opacity for team
  Color getColorWithOpacity(Team team, double opacity) {
    return getBaseColor(team).withValues(alpha: opacity);
  }

  /// Update color for a specific team
  TeamColorScheme withTeamColor(Team team, Color color) {
    final newPalettes = Map<Team, TeamColorPalette>.from(_teamPalettes);
    newPalettes[team] = TeamColorPalette.fromBaseColor(color);
    return TeamColorScheme(newPalettes);
  }

  /// Convert to serializable format (color values as integers)
  Map<String, int> toMap() {
    return {
      'team_a_color':
          _teamPalettes[Team.a]?.baseColor.toARGB32() ??
          TeamColorPalette.defaultTeamA().baseColor.toARGB32(),
      'team_b_color':
          _teamPalettes[Team.b]?.baseColor.toARGB32() ??
          TeamColorPalette.defaultTeamB().baseColor.toARGB32(),
    };
  }

  /// Create from serializable format
  factory TeamColorScheme.fromMap(Map<String, dynamic> map) {
    return TeamColorScheme.fromBaseColors(
      teamAColor: Color(
        map['team_a_color'] ??
            TeamColorPalette.defaultTeamA().baseColor.toARGB32(),
      ),
      teamBColor: Color(
        map['team_b_color'] ??
            TeamColorPalette.defaultTeamB().baseColor.toARGB32(),
      ),
    );
  }
}
