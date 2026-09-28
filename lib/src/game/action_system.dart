import 'dart:async';

import 'package:collection/collection.dart';
import 'package:rise_together_game/src/models/player_action.dart';
import 'package:rise_together_game/src/models/team_context.dart';
import 'package:rise_together_game/src/models/team_thrust.dart';

/// Manages action streams for a specific team
class TeamActionStream {
  // TODO: too many non-final fields in team / action stream
  TeamDisplayPosition position;
  int teamId; // Assigned by coordinator
  final int maxPlayers;
  final StreamController<GameAction> _controller =
      StreamController<GameAction>.broadcast();
  final Map<String, PaddleAction> _currentActions = {};

  // Callback to get player bitflag mapping
  final Map<String, int> Function()? _getPlayerBitflags;

  Stream<GameAction> get actionStream => _controller.stream;
  Stream<TeamThrust> get thrustStream =>
      _controller.stream.map((_) => _calculateThrust());

  // Configured team player count (for proper thrust calculation)
  int? _configuredTeamPlayerCount;

  TeamActionStream({
    required this.position,
    required this.maxPlayers,
    Map<String, int> Function()? getPlayerBitflags,
  }) : _getPlayerBitflags = getPlayerBitflags,
       // default teamId based on position
       teamId = position == TeamDisplayPosition.left ? 0 : 1;

  /// Set the configured team player count for proper thrust calculation
  void setConfiguredTeamPlayerCount(int count) {
    _configuredTeamPlayerCount = count;
  }

  void addAction(GameAction action) {
    _currentActions[action.playerId] = action.action;
    _controller.add(action);
  }

  void removePlayer(String playerId) {
    _currentActions.remove(playerId);
    _controller.add(GameAction(playerId, PaddleAction.none));
  }

  /// Clear all current actions for all players (used when ball hits wall)
  void clearAllActions() {
    final playerIds = _currentActions.keys.toList();

    for (final playerId in playerIds) {
      // final previousAction = _currentActions[playerId];
      _currentActions[playerId] = PaddleAction.none;
      _controller.add(GameAction(playerId, PaddleAction.none));
    }
  }

  TeamThrust _calculateThrust() {
    final leftCount = _currentActions.values
        .where((a) => a == PaddleAction.left)
        .length;
    final rightCount = _currentActions.values
        .where((a) => a == PaddleAction.right)
        .length;
    final activeCount = leftCount + rightCount;

    // Use configured team size if available, otherwise fall back to current team size
    final teamSize = _configuredTeamPlayerCount ?? _currentActions.keys.length;
    final thrustPerPlayer = teamSize > 0 ? 1.0 / teamSize : 0.0;

    // Calculate bitflags for left and right inputs
    int leftBitflags = 0;
    int rightBitflags = 0;

    if (_getPlayerBitflags != null) {
      final playerBitflags = _getPlayerBitflags();

      for (final entry in _currentActions.entries) {
        final playerId = entry.key;
        final action = entry.value;
        final playerBitflag = playerBitflags[playerId] ?? 0;

        // Debug logging when there's an active action

        if (action == PaddleAction.left) {
          leftBitflags |= playerBitflag;
        } else if (action == PaddleAction.right) {
          rightBitflags |= playerBitflag;
        }
      }
    }

    return TeamThrust(
      leftThrust: leftCount * thrustPerPlayer,
      rightThrust: rightCount * thrustPerPlayer,
      activePlayerCount: activeCount,
      leftBitflags: leftBitflags,
      rightBitflags: rightBitflags,
    );
  }

  TeamThrust getCurrentThrust() => _calculateThrust();

  void dispose() {
    _controller.close();
  }
}

/// Manages multiple team action streams
class ActionStreamManager {
  final Map<TeamDisplayPosition, TeamActionStream> _teamStreams = {};

  TeamActionStream createTeamStream(
    TeamDisplayPosition position,
    int maxPlayers, {
    Map<String, int> Function()? getPlayerBitflags,
  }) {
    final stream = TeamActionStream(
      position: position,
      maxPlayers: maxPlayers,
      getPlayerBitflags: getPlayerBitflags,
    );
    _teamStreams[position] = stream;
    return stream;
  }

  TeamActionStream? getTeamStream(int teamId) =>
      _teamStreams.values.firstWhereOrNull((stream) => stream.teamId == teamId);
  TeamActionStream? getTeamStreamByPosition(TeamDisplayPosition pos) =>
      _teamStreams[pos];

  void dispose() {
    for (final stream in _teamStreams.values) {
      stream.dispose();
    }
    _teamStreams.clear();
  }
}
