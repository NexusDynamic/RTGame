import 'package:flutter/material.dart';
import 'package:rise_together_game/src/models/team.dart';
import 'package:rise_together_game/src/models/team_colors.dart';
import 'package:rise_together_game/src/settings/app_settings.dart';

/// Mixin that provides convenient access to team colors throughout the app
mixin TeamColorProvider on AppSettings {
  /// Get the current team color scheme from settings
  TeamColorScheme get teamColorScheme {
    final teamAColorValue = appSettings.getInt('colors.team_a_color');
    final teamBColorValue = appSettings.getInt('colors.team_b_color');

    return TeamColorScheme.fromBaseColors(
      teamAColor: Color(teamAColorValue),
      teamBColor: Color(teamBColorValue),
    );
  }

  /// Get base color for a team
  Color getTeamBaseColor(Team team) => teamColorScheme.getBaseColor(team);

  /// Get light color for a team
  Color getTeamLightColor(Team team) => teamColorScheme.getLightColor(team);

  /// Get dark color for a team
  Color getTeamDarkColor(Team team) => teamColorScheme.getDarkColor(team);

  /// Get accent color for a team
  Color getTeamAccentColor(Team team) => teamColorScheme.getAccentColor(team);

  /// Get background color for a team
  Color getTeamBackgroundColor(Team team) =>
      teamColorScheme.getBackgroundColor(team);

  /// Get text color for a team
  Color getTeamTextColor(Team team) => teamColorScheme.getTextColor(team);

  /// Get color with specific opacity for team
  Color getTeamColorWithOpacity(Team team, double opacity) =>
      teamColorScheme.getColorWithOpacity(team, opacity);

  /// Update team color in settings
  void setTeamColor(Team team, Color color) {
    final key = team == Team.a ? 'colors.team_a_color' : 'colors.team_b_color';
    appSettings.setInt(key, color.toARGB32());
  }
}
